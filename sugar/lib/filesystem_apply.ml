type resolved_target = {
  parent : string;
  path : string;
  mode : int;
}

type boundary_error =
  | Usage of string
  | Internal of string
  | Conflict of Conflict.t

let ( let* ) = Result.bind

external platform_replace_file : string -> string -> unit
  = "monika_sugar_replace_file"

external platform_is_reparse_point : string -> bool
  = "monika_sugar_is_reparse_point"

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

let internal_result message =
  command_result
    ~termination:(Command_result.Internal_failure message)
    ~effect:Command_result.No_change
    ~summary:[ ("message", Command_result.Text message) ]
    ()

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
    (Conflict.Filesystem_safety
       {
         patch_id = Proposed_patch.id patch;
         target = Proposed_patch.target patch;
         reason;
       })

let missing_artifact patch =
  Conflict
    (Conflict.Missing_artifact
       {
         patch_id = Proposed_patch.id patch;
         target = Proposed_patch.target patch;
       })

let unix_error function_name arg error =
  let message = Unix.error_message error in
  if String.length arg = 0 then function_name ^ ": " ^ message
  else function_name ^ "(" ^ arg ^ "): " ^ message

let protect f =
  try f () with
  | Unix.Unix_error (error, function_name, arg) ->
      Error (Internal (unix_error function_name arg error))
  | Sys_error message -> Error (Internal message)
  | Failure message -> Error (Internal message)

let resolve_root workspace =
  protect (fun () ->
      let root = Unix.realpath workspace in
      let stats = Unix.stat root in
      if stats.st_kind = Unix.S_DIR then Ok root
      else Error (Usage "workspace must be an existing directory"))
  |> function
  | Ok _ as ok -> ok
  | Error (Internal message) -> Error (Usage message)
  | Error _ as error -> error

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

let directory_contains_exact dir segment =
  protect (fun () ->
      Sys.readdir dir |> Array.exists (String.equal segment) |> fun value ->
      Ok value)

let exact_entry_or_error patch dir segment candidate =
  match directory_contains_exact dir segment with
  | Ok true -> Ok ()
  | Ok false ->
      if Sys.file_exists candidate then
        Error (patch_conflict patch Conflict.Native_spelling_mismatch)
      else Error (missing_artifact patch)
  | Error _ as error -> error

let reject_reparse_point patch path =
  protect (fun () ->
      if platform_is_reparse_point path then
        Error (patch_conflict patch Conflict.Reparse_point)
      else Ok ())

let lstat path = protect (fun () -> Ok (Unix.lstat path))

let resolve_target root patch =
  let rec parents current = function
    | [] -> invalid_arg "workspace path has no final segment"
    | [ final ] ->
        let* () = validate_native_segment patch final in
        let path = Filename.concat current final in
        let* () = exact_entry_or_error patch current final path in
        let* () = reject_reparse_point patch path in
        let* stats = lstat path in
        (match stats.Unix.st_kind with
        | Unix.S_REG ->
            Ok { parent = current; path; mode = stats.Unix.st_perm }
        | Unix.S_LNK ->
            Error (patch_conflict patch Conflict.Target_is_symlink)
        | _ ->
            Error (patch_conflict patch Conflict.Target_not_regular_file))
    | segment :: rest ->
        let* () = validate_native_segment patch segment in
        let path = Filename.concat current segment in
        let* () = exact_entry_or_error patch current segment path in
        let* () = reject_reparse_point patch path in
        let* stats = lstat path in
        (match stats.Unix.st_kind with
        | Unix.S_DIR -> parents path rest
        | Unix.S_LNK ->
            Error (patch_conflict patch Conflict.Symlink_component)
        | _ ->
            Error (patch_conflict patch Conflict.Parent_not_directory))
  in
  parents root (Workspace_path.segments (Proposed_patch.target patch))

let read_file path =
  protect (fun () ->
      let input = open_in_bin path in
      Fun.protect
        ~finally:(fun () -> close_in_noerr input)
        (fun () ->
          let length = in_channel_length input in
          Ok (really_input_string input length)))

let snapshot_for patch content =
  Workspace_snapshot.make [ (Proposed_patch.target patch, content) ]
  |> function
  | Ok snapshot -> Ok snapshot
  | Error message -> Error (Internal message)

let content_from_snapshot target snapshot =
  match Workspace_snapshot.find target snapshot with
  | Some file -> Ok (Workspace_snapshot.file_content file)
  | None -> Error (Internal "applied snapshot did not contain target")

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
  protect (fun () ->
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

let flush_directory dir =
  if not Sys.win32 then
    try
      let fd = Unix.openfile dir [ Unix.O_RDONLY; Unix.O_CLOEXEC ] 0 in
      Fun.protect
        ~finally:(fun () -> Unix.close fd)
        (fun () -> Unix.fsync fd)
    with _ -> ()

let remove_if_exists path = try Sys.remove path with Sys_error _ -> ()

let write_temp_file target content =
  protect (fun () ->
      let temp_path, output =
        Filename.open_temp_file ~mode:[ Open_binary ] ~temp_dir:target.parent
          ".monika-apply-" ".tmp"
      in
      let cleanup () = remove_if_exists temp_path in
      try
        output_string output content;
        flush output;
        let fd = Unix.descr_of_out_channel output in
        Unix.fsync fd;
        Unix.chmod temp_path target.mode;
        Unix.fsync fd;
        close_out output;
        Ok temp_path
      with exn ->
        close_out_noerr output;
        cleanup ();
        raise exn)

let verify_expected_identity patch root =
  let* target = resolve_target root patch in
  let* content = read_file target.path in
  let actual = Content_identity.of_content content in
  if Content_identity.equal actual (Proposed_patch.expected_identity patch)
  then Ok target
  else
    Error
      (Conflict
         (Conflict.Identity_mismatch
            {
              patch_id = Proposed_patch.id patch;
              target = Proposed_patch.target patch;
              expected = Proposed_patch.expected_identity patch;
              actual;
            }))

let verify_resulting_identity patch target =
  let* content = read_file target.path in
  let actual = Content_identity.of_content content in
  if Content_identity.equal actual (Proposed_patch.resulting_identity patch)
  then Ok ()
  else
    Error
      (Conflict
         (Conflict.Result_identity_mismatch
            {
              patch_id = Proposed_patch.id patch;
              target = Proposed_patch.target patch;
              declared = Proposed_patch.resulting_identity patch;
              actual;
            }))

let replace_and_verify patch root target content changed =
  let* temp_path = write_temp_file target content in
  match verify_expected_identity patch root with
  | Error error ->
      remove_if_exists temp_path;
      Error error
  | Ok latest_target -> (
      try
        platform_replace_file temp_path latest_target.path;
        flush_directory latest_target.parent;
        match verify_resulting_identity patch latest_target with
        | Ok () -> Ok (applied_result changed)
        | Error error -> Error error
      with exn ->
        remove_if_exists temp_path;
        Error (Internal (Printexc.to_string exn)))

let run_apply ~root ~patch ~dry_run =
  let* target = resolve_target root patch in
  let* content = read_file target.path in
  let* pure_result = apply_pure patch content in
  match pure_result with
  | `No_change -> Ok (no_change_result ())
  | `Applied (changed, resulting_content) ->
      if dry_run then Ok (dry_run_result patch)
      else replace_and_verify patch root target resulting_content changed

let apply ~workspace ~patch ~dry_run =
  match resolve_root workspace with
  | Error (Usage message) -> usage_result message
  | Error (Internal message) -> internal_result message
  | Error (Conflict conflict) -> conflict_result conflict
  | Ok root -> (
      match
        with_target_lock root patch (fun () -> run_apply ~root ~patch ~dry_run)
      with
      | Ok result -> result
      | Error (Usage message) -> usage_result message
      | Error (Internal message) -> internal_result message
      | Error (Conflict conflict) -> conflict_result conflict)
