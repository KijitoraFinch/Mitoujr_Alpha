type posix_target = {
  parent_fd : Unix.file_descr;
  name : string;
  mode : int;
  exists : bool;
}

type internal_code = Filesystem_io | Internal_invariant | Resource_exhausted

type internal_failure = {
  code : internal_code;
  operation : string;
  target : Workspace_path.t option;
  commit_state : Filesystem_commit.commit_state option;
}

type boundary_error =
  | Usage of string
  | Internal of internal_failure
  | Conflict of Conflict.t

let ( let* ) = Result.bind

let command_result ?summary ~termination ~effect ?(patches = [])
    ?(changed_artifacts = []) ?(conflicts = []) () =
  match
    Command_result.make ~command:"apply" ~termination ~effect ~patches
      ~changed_artifacts ~conflicts ?summary ()
  with
  | Ok result -> result
  | Error message -> invalid_arg ("invalid apply CommandResult: " ^ message)

let usage_result message =
  command_result
    ~termination:(Command_result.Usage_failure message)
    ~effect:Command_result.No_change
    ~summary:[ ("message", Command_result.Text message) ]
    ()

let internal_code_string = function
  | Filesystem_io -> "filesystem-io"
  | Internal_invariant -> "internal-invariant"
  | Resource_exhausted -> "resource-exhausted"

let internal_result failure =
  let summary =
    [
      ("errorCode", Command_result.Text (internal_code_string failure.code));
      ("operation", Command_result.Text failure.operation);
    ]
    @
    match failure.target with
    | None -> []
    | Some target ->
        [
          ( "location",
            Command_result.Text (Workspace_path.to_canonical_string target) );
        ]
  in
  let summary =
    summary
    @
    match failure.commit_state with
    | None -> []
    | Some Filesystem_commit.Not_committed ->
        [ ("commitState", Command_result.Text "not-committed") ]
    | Some Filesystem_commit.Committed_or_unknown ->
        [ ("commitState", Command_result.Text "committed-or-unknown") ]
  in
  command_result
    ~termination:(Command_result.Internal_failure "internal operation failed")
    ~effect:Command_result.No_change
    ~summary ()

let conflict_result conflict =
  command_result ~termination:Command_result.Completed
    ~effect:Command_result.Conflicted ~conflicts:[ conflict ]
    ~summary:[ ("conflicts", Command_result.Count 1) ]
    ()

let no_change_result () =
  command_result ~termination:Command_result.Completed
    ~effect:Command_result.No_change
    ~summary:[ ("applied", Command_result.Count 0) ]
    ()

let dry_run_result patch =
  command_result ~termination:Command_result.Completed
    ~effect:Command_result.Patches_proposed ~patches:[ patch ]
    ~summary:[ ("wouldApply", Command_result.Count 1) ]
    ()

let applied_result changed =
  command_result ~termination:Command_result.Completed
    ~effect:Command_result.Applied ~changed_artifacts:[ changed ]
    ~summary:[ ("applied", Command_result.Count 1) ]
    ()

let patch_conflict patch reason =
  Conflict
    (Conflict.filesystem_safety ~patch_id:(Proposed_patch.id patch)
       ~target:(Proposed_patch.target patch) ~reason)

let missing_artifact patch =
  Conflict
    (Conflict.missing_artifact ~patch_id:(Proposed_patch.id patch)
       ~target:(Proposed_patch.target patch))

let valid_conflict = function
  | Ok conflict -> conflict
  | Error message -> invalid_arg ("invalid filesystem conflict: " ^ message)

let internal ?target ?(code = Filesystem_io) operation =
  Internal { code; operation; target; commit_state = None }

let protect ?target operation f =
  try f () with
  | Unix.Unix_error _ | Sys_error _ | End_of_file | Failure _ ->
      Error (internal ?target operation)

let resolve_root workspace =
  try
    let root = Unix.realpath workspace in
    let stats = Unix.stat root in
    if stats.st_kind = Unix.S_DIR then Ok root
    else Error (Usage "workspace must be an existing directory")
  with Unix.Unix_error _ | Sys_error _ ->
    Error (Usage "workspace must be an existing directory")

let valid_utf8 value =
  let length = String.length value in
  let continuation index =
    index < length
    &&
    let byte = Char.code value.[index] in
    byte >= 0x80 && byte <= 0xbf
  in
  let rec loop index =
    if index = length then true
    else
      let byte = Char.code value.[index] in
      if byte <= 0x7f then loop (index + 1)
      else if byte >= 0xc2 && byte <= 0xdf then
        continuation (index + 1) && loop (index + 2)
      else if byte = 0xe0 then
        index + 2 < length
        &&
        let b1 = Char.code value.[index + 1] in
        b1 >= 0xa0 && b1 <= 0xbf && continuation (index + 2)
        && loop (index + 3)
      else if (byte >= 0xe1 && byte <= 0xec) || byte = 0xee || byte = 0xef
      then continuation (index + 1) && continuation (index + 2)
           && loop (index + 3)
      else if byte = 0xed then
        index + 2 < length
        &&
        let b1 = Char.code value.[index + 1] in
        b1 >= 0x80 && b1 <= 0x9f && continuation (index + 2)
        && loop (index + 3)
      else if byte = 0xf0 then
        index + 3 < length
        &&
        let b1 = Char.code value.[index + 1] in
        b1 >= 0x90 && b1 <= 0xbf && continuation (index + 2)
        && continuation (index + 3) && loop (index + 4)
      else if byte >= 0xf1 && byte <= 0xf3 then
        continuation (index + 1) && continuation (index + 2)
        && continuation (index + 3) && loop (index + 4)
      else if byte = 0xf4 then
        index + 3 < length
        &&
        let b1 = Char.code value.[index + 1] in
        b1 >= 0x80 && b1 <= 0x8f && continuation (index + 2)
        && continuation (index + 3) && loop (index + 4)
      else false
  in
  loop 0

let ascii_uppercase value =
  String.map
    (function 'a' .. 'z' as char ->
      Char.chr (Char.code char - Char.code 'a' + Char.code 'A')
    | char -> char)
    value

let windows_reserved_device segment =
  let base =
    match String.index_opt segment '.' with
    | None -> segment
    | Some index -> String.sub segment 0 index
  in
  match ascii_uppercase base with
  | "CON" | "PRN" | "AUX" | "NUL" -> true
  | value
    when String.length value = 4
         && (String.sub value 0 3 = "COM" || String.sub value 0 3 = "LPT")
         && value.[3] >= '1' && value.[3] <= '9' ->
      true
  | _ -> false

let windows_reserved_char = function
  | '<' | '>' | ':' | '"' | '\\' | '|' | '?' | '*' -> true
  | char -> Char.code char < 0x20

let validate_native_segment patch segment =
  if not Sys.win32 then Ok ()
  else if not (valid_utf8 segment) then
    Error (patch_conflict patch Conflict.Invalid_native_path)
  else if String.exists windows_reserved_char segment then
    Error (patch_conflict patch Conflict.Invalid_native_path)
  else if
    let last = segment.[String.length segment - 1] in
    last = ' ' || last = '.'
  then Error (patch_conflict patch Conflict.Invalid_native_path)
  else if windows_reserved_device segment then
    Error (patch_conflict patch Conflict.Invalid_native_path)
  else Ok ()

let read_descriptor patch descriptor =
  protect ~target:(Proposed_patch.target patch) "read-target" (fun () ->
      let buffer = Bytes.create 65536 in
      let output = Buffer.create 65536 in
      let rec loop () =
        match Unix.read descriptor buffer 0 (Bytes.length buffer) with
        | 0 -> Ok (Buffer.contents output)
        | count ->
            Buffer.add_subbytes output buffer 0 count;
            loop ()
      in
      loop ())

let close_noerr descriptor = try Unix.close descriptor with Unix.Unix_error _ -> ()

let with_descriptor descriptor operation =
  Fun.protect ~finally:(fun () -> close_noerr descriptor) operation

let posix_exact_entry patch directory segment =
  let* entries =
    protect ~target:(Proposed_patch.target patch) "enumerate-parent" (fun () ->
        Ok (Filesystem_handle.entries directory))
  in
  if List.exists (String.equal segment) entries then Ok ()
  else
    try
      ignore (Filesystem_handle.entry_kind_at directory segment);
      Error (patch_conflict patch Conflict.Native_spelling_mismatch)
    with
    | Unix.Unix_error (Unix.ENOENT, _, _) -> Error (missing_artifact patch)
    | Unix.Unix_error _ ->
        Error
          (internal ~target:(Proposed_patch.target patch)
             "inspect-path-component")

let open_posix_regular patch parent name =
  try Ok (Filesystem_handle.open_regular_at parent name) with
  | Unix.Unix_error (Unix.ELOOP, _, _) ->
      Error
        (patch_conflict patch
           (if Sys.win32 then Conflict.Reparse_point
            else Conflict.Target_is_symlink))
  | Unix.Unix_error ((Unix.EISDIR | Unix.EINVAL), _, _) ->
      Error (patch_conflict patch Conflict.Target_not_regular_file)
  | Unix.Unix_error (Unix.ENOENT, _, _) -> Error (missing_artifact patch)
  | Unix.Unix_error _ ->
      Error (internal ~target:(Proposed_patch.target patch) "open-target")

let open_posix_parent patch parent name =
  try Ok (Filesystem_handle.open_dir_at parent name) with
  | Unix.Unix_error (Unix.ELOOP, _, _) ->
      Error
        (patch_conflict patch
           (if Sys.win32 then Conflict.Reparse_point
            else Conflict.Symlink_component))
  | Unix.Unix_error ((Unix.ENOTDIR | Unix.EINVAL), _, _) ->
      Error (patch_conflict patch Conflict.Parent_not_directory)
  | Unix.Unix_error (Unix.ENOENT, _, _) -> Error (missing_artifact patch)
  | Unix.Unix_error _ ->
      Error
        (internal ~target:(Proposed_patch.target patch) "open-parent")

let posix_target_after_open patch parent_fd name descriptor =
  let stats = Unix.fstat descriptor in
  match stats.Unix.st_kind with
  | Unix.S_REG ->
      Ok { parent_fd; name; mode = stats.Unix.st_perm; exists = true }
  | Unix.S_LNK -> Error (patch_conflict patch Conflict.Target_is_symlink)
  | _ -> Error (patch_conflict patch Conflict.Target_not_regular_file)

let resolve_posix_target ?(allow_missing = false) root patch =
  let rec parents current = function
    | [] ->
        close_noerr current;
        invalid_arg "workspace path has no final segment"
    | [ final ] ->
        let result =
          let* () = validate_native_segment patch final in
          let* entries =
            protect ~target:(Proposed_patch.target patch) "enumerate-parent"
              (fun () -> Ok (Filesystem_handle.entries current))
          in
          if not (List.exists (String.equal final) entries) then
            try
              ignore (Filesystem_handle.entry_kind_at current final);
              Error (patch_conflict patch Conflict.Native_spelling_mismatch)
            with
            | Unix.Unix_error (Unix.ENOENT, _, _) when allow_missing ->
                Ok
                  {
                    parent_fd = current;
                    name = final;
                    mode = 0o644;
                    exists = false;
                  }
            | Unix.Unix_error (Unix.ENOENT, _, _) ->
                Error (missing_artifact patch)
            | Unix.Unix_error _ ->
                Error
                  (internal ~target:(Proposed_patch.target patch)
                     "inspect-path-component")
          else
            let* kind =
              protect ~target:(Proposed_patch.target patch)
                "inspect-path-component" (fun () ->
                  Ok (Filesystem_handle.entry_kind_at current final))
            in
            match kind with
            | Filesystem_handle.Symlink ->
                Error (patch_conflict patch Conflict.Target_is_symlink)
            | Filesystem_handle.Reparse_point ->
                Error (patch_conflict patch Conflict.Reparse_point)
            | Filesystem_handle.Directory | Filesystem_handle.Other ->
                Error (patch_conflict patch Conflict.Target_not_regular_file)
            | Filesystem_handle.Regular_file -> (
                match open_posix_regular patch current final with
                | Error error -> Error error
                | Ok descriptor ->
                    let opened =
                      protect ~target:(Proposed_patch.target patch)
                        "inspect-target" (fun () ->
                          posix_target_after_open patch current final descriptor)
                    in
                    close_noerr descriptor;
                    opened)
        in
        (match result with
        | Ok _ -> result
        | Error _ ->
            close_noerr current;
            result)
    | segment :: rest ->
        let next =
          let* () = validate_native_segment patch segment in
          let* () = posix_exact_entry patch current segment in
          let* kind =
            protect ~target:(Proposed_patch.target patch)
              "inspect-path-component" (fun () ->
                Ok (Filesystem_handle.entry_kind_at current segment))
          in
          match kind with
          | Filesystem_handle.Symlink ->
              Error (patch_conflict patch Conflict.Symlink_component)
          | Filesystem_handle.Reparse_point ->
              Error (patch_conflict patch Conflict.Reparse_point)
          | Filesystem_handle.Regular_file | Filesystem_handle.Other ->
              Error (patch_conflict patch Conflict.Parent_not_directory)
          | Filesystem_handle.Directory -> open_posix_parent patch current segment
        in
        (match next with
        | Error error ->
            close_noerr current;
            Error error
        | Ok next ->
            close_noerr current;
            parents next rest)
  in
  let* root_fd =
    protect ~target:(Proposed_patch.target patch) "open-workspace" (fun () ->
        Ok (Filesystem_handle.open_root root))
  in
  parents root_fd (Workspace_path.segments (Proposed_patch.target patch))

let snapshot_for patch content =
  Workspace_snapshot.make
    (match content with
    | None -> []
    | Some content -> [ (Proposed_patch.target patch, content) ])
  |> function
  | Ok snapshot -> Ok snapshot
  | Error _ ->
      Error
        (internal ~code:Internal_invariant
           ~target:(Proposed_patch.target patch) "construct-workspace-snapshot")

let content_from_snapshot target snapshot =
  match Workspace_snapshot.find target snapshot with
  | Some file -> Ok (Workspace_snapshot.file_content file)
  | None ->
      Error
        (internal ~code:Internal_invariant ~target
           "read-applied-workspace-snapshot")

let apply_pure patch content =
  let* snapshot = snapshot_for patch content in
  match Workspace_ops.apply_patch snapshot patch with
  | Workspace_ops.Applied applied ->
      let* content =
        content_from_snapshot (Proposed_patch.target patch) applied.snapshot
      in
      Ok (`Applied (applied.changed, content))
  | Workspace_ops.No_change _ -> Ok `No_change
  | Workspace_ops.Conflict conflict -> Error (Conflict conflict)

let lock_path root patch =
  let key =
    root ^ "\000"
    ^ (Proposed_patch.target patch |> Workspace_path.to_canonical_string)
  in
  let digest = Content_digest.of_content key |> Content_digest.to_hex in
  Filename.concat (Filename.get_temp_dir_name ())
    ("monika-apply-" ^ digest ^ ".lock")

let with_target_lock root patch f =
  protect ~target:(Proposed_patch.target patch) "acquire-target-lock" (fun () ->
      let fd =
        Unix.openfile (lock_path root patch)
          [ Unix.O_CREAT; Unix.O_RDWR; Unix.O_CLOEXEC ]
          0o600
      in
      Fun.protect
        ~finally:(fun () ->
          (try Unix.lockf fd Unix.F_ULOCK 0 with _ -> ());
          Unix.close fd)
        (fun () ->
          Unix.lockf fd Unix.F_LOCK 0;
          f ()))

let flush_posix_directory patch descriptor =
  if Sys.win32 then Ok ()
  else try
    Unix.fsync descriptor;
    Ok ()
  with
  | Unix.Unix_error ((Unix.EINVAL | Unix.ENOSYS | Unix.EOPNOTSUPP), _, _) ->
      Ok ()
  | Unix.Unix_error _ ->
      Error (internal ~target:(Proposed_patch.target patch) "flush-parent")

let temporary_counter = ref 0

let create_posix_temporary patch parent_fd =
  let rec attempt remaining =
    if remaining = 0 then
      Error
        (internal ~code:Resource_exhausted
           ~target:(Proposed_patch.target patch) "allocate-temporary-name")
    else (
      incr temporary_counter;
      let name =
        Printf.sprintf ".monika-apply-%d-%08x.tmp" (Unix.getpid ())
          !temporary_counter
      in
      try
        let descriptor =
          Filesystem_handle.create_exclusive_at parent_fd name 0o600
        in
        Ok (name, descriptor)
      with
      | Unix.Unix_error (Unix.EEXIST, _, _) -> attempt (remaining - 1)
      | Unix.Unix_error _ ->
          Error
            (internal ~target:(Proposed_patch.target patch)
               "create-temporary"))
  in
  attempt 128

let unlink_posix_noerr parent_fd name =
  try Filesystem_handle.unlink_at parent_fd name with Unix.Unix_error _ -> ()

let write_all patch descriptor content =
  protect ~target:(Proposed_patch.target patch) "write-temporary" (fun () ->
      let rec loop offset =
        if offset = String.length content then Ok ()
        else
          let count =
            Unix.write_substring descriptor content offset
              (String.length content - offset)
          in
          if count = 0 then
            Error
              (internal ~target:(Proposed_patch.target patch)
                 "write-temporary")
          else loop (offset + count)
      in
      loop 0)

let write_posix_temporary patch target content =
  let* name, descriptor = create_posix_temporary patch target.parent_fd in
  let result =
    let* () = write_all patch descriptor content in
    let* () =
      protect ~target:(Proposed_patch.target patch) "flush-temporary" (fun () ->
          Unix.fsync descriptor;
          Ok ())
    in
    let* () =
      if Sys.win32 then Ok ()
      else
        protect ~target:(Proposed_patch.target patch) "set-temporary-metadata"
          (fun () ->
            Unix.fchmod descriptor target.mode;
            Ok ())
    in
    protect ~target:(Proposed_patch.target patch) "flush-temporary-metadata"
      (fun () ->
        Unix.fsync descriptor;
        Ok ())
  in
  close_noerr descriptor;
  match result with
  | Ok () -> Ok name
  | Error error ->
      unlink_posix_noerr target.parent_fd name;
      Error error

let read_posix_target patch target =
  try
    let descriptor =
      Filesystem_handle.open_regular_at target.parent_fd target.name
    in
    with_descriptor descriptor (fun () -> read_descriptor patch descriptor)
  with
  | Unix.Unix_error ((Unix.ELOOP | Unix.EISDIR), _, _) ->
      Error (patch_conflict patch Conflict.Target_not_regular_file)
  | Unix.Unix_error (Unix.ENOENT, _, _) -> Error (missing_artifact patch)
  | Unix.Unix_error _ ->
      Error (internal ~target:(Proposed_patch.target patch) "open-target")

let verify_posix_expected_identity patch target =
  let* content = read_posix_target patch target in
  let actual = Content_identity.of_content content in
  match Proposed_patch.operation patch with
  | Proposed_patch.Create _ ->
      Error
        (Conflict
           (Conflict.artifact_already_exists
              ~patch_id:(Proposed_patch.id patch)
              ~target:(Proposed_patch.target patch) ~actual))
  | Proposed_patch.Edit { expected_identity; _ } ->
      if Content_identity.equal actual expected_identity then Ok ()
      else
        Error
          (Conflict
             (Conflict.identity_mismatch ~patch_id:(Proposed_patch.id patch)
                ~target:(Proposed_patch.target patch)
                ~expected:expected_identity ~actual
             |> valid_conflict))

let verify_posix_absent patch target =
  let* entries =
    protect ~target:(Proposed_patch.target patch) "enumerate-parent" (fun () ->
        Ok (Filesystem_handle.entries target.parent_fd))
  in
  if List.exists (String.equal target.name) entries then
    verify_posix_expected_identity patch { target with exists = true }
  else
    try
      ignore (Filesystem_handle.entry_kind_at target.parent_fd target.name);
      Error (patch_conflict patch Conflict.Native_spelling_mismatch)
    with
    | Unix.Unix_error (Unix.ENOENT, _, _) -> Ok ()
    | Unix.Unix_error _ ->
        Error
          (internal ~target:(Proposed_patch.target patch)
             "inspect-path-component")

let verify_posix_resulting_identity patch target =
  let* content = read_posix_target patch target in
  let actual = Content_identity.of_content content in
  if Content_identity.equal actual (Proposed_patch.resulting_identity patch)
  then Ok ()
  else
    Error
      (Conflict
         (Conflict.result_identity_mismatch ~patch_id:(Proposed_patch.id patch)
            ~target:(Proposed_patch.target patch)
            ~declared:(Proposed_patch.resulting_identity patch) ~actual
         |> valid_conflict))

let replace_posix_and_verify patch target content changed =
  let operations : (string, boundary_error) Filesystem_commit.operations =
    {
      prepare_temporary =
        (fun () -> write_posix_temporary patch target content);
      cleanup_temporary = unlink_posix_noerr target.parent_fd;
      verify_source = (fun () -> verify_posix_expected_identity patch target);
      atomic_replace =
        (fun temporary_name ->
          try
            Filesystem_handle.rename_at target.parent_fd temporary_name
              target.parent_fd target.name;
            Ok ()
          with Unix.Unix_error _ ->
            Error
              (internal ~target:(Proposed_patch.target patch)
                 "atomic-replace"));
      flush_parent = (fun () -> flush_posix_directory patch target.parent_fd);
      verify_result = (fun () -> verify_posix_resulting_identity patch target);
    }
  in
  match Filesystem_commit.run operations with
  | Ok () -> Ok (applied_result changed)
  | Error failure -> (
      match failure.cause with
      | Internal cause ->
          Error
            (Internal
               {
                 cause with
                 commit_state = Some failure.commit_state;
               })
      | (Usage _ | Conflict _) as cause -> Error cause)

let create_posix_and_verify patch target content changed =
  let operations : (string, boundary_error) Filesystem_commit.operations =
    {
      prepare_temporary =
        (fun () -> write_posix_temporary patch target content);
      cleanup_temporary = unlink_posix_noerr target.parent_fd;
      verify_source = (fun () -> verify_posix_absent patch target);
      atomic_replace =
        (fun temporary_name ->
          try
            Filesystem_handle.rename_noreplace_at target.parent_fd
              temporary_name target.parent_fd target.name;
            Ok ()
          with
          | Unix.Unix_error (Unix.EEXIST, _, _) ->
              verify_posix_expected_identity patch
                { target with exists = true }
          | Unix.Unix_error _ ->
              Error
                (internal ~target:(Proposed_patch.target patch)
                   "atomic-create"));
      flush_parent = (fun () -> flush_posix_directory patch target.parent_fd);
      verify_result = (fun () -> verify_posix_resulting_identity patch target);
    }
  in
  match Filesystem_commit.run operations with
  | Ok () -> Ok (applied_result changed)
  | Error failure -> (
      match failure.cause with
      | Internal cause ->
          Error
            (Internal
               {
                 cause with
                 commit_state = Some failure.commit_state;
               })
      | (Usage _ | Conflict _) as cause -> Error cause)

let run_apply_posix ~root ~patch ~dry_run =
  let creating =
    match Proposed_patch.operation patch with
    | Proposed_patch.Create _ -> true
    | Proposed_patch.Edit _ -> false
  in
  let* target = resolve_posix_target ~allow_missing:creating root patch in
  Fun.protect
    ~finally:(fun () -> close_noerr target.parent_fd)
    (fun () ->
      let* current_content =
        if target.exists then
          read_posix_target patch target |> Result.map Option.some
        else Ok None
      in
      let* pure_result = apply_pure patch current_content in
      match pure_result with
      | `No_change -> Ok (no_change_result ())
      | `Applied (changed, resulting_content) ->
          if dry_run then Ok (dry_run_result patch)
          else if creating then
            create_posix_and_verify patch target resulting_content changed
          else
            replace_posix_and_verify patch target resulting_content changed)

let apply ~workspace ~patch ~dry_run =
  match resolve_root workspace with
  | Error (Usage message) -> usage_result message
  | Error (Internal message) -> internal_result message
  | Error (Conflict conflict) -> conflict_result conflict
  | Ok root -> (
      match
        with_target_lock root patch (fun () ->
            run_apply_posix ~root ~patch ~dry_run)
      with
      | Ok result -> result
      | Error (Usage message) -> usage_result message
      | Error (Internal message) -> internal_result message
      | Error (Conflict conflict) -> conflict_result conflict)
