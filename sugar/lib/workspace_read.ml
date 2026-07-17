type safety_reason =
  | Native_spelling_mismatch
  | Symlink_component
  | Reparse_point
  | Parent_not_directory
  | Target_not_regular_file

type error =
  | Invalid_workspace
  | Missing_artifact
  | Unsafe of safety_reason
  | Unstable_content
  | Filesystem_io of string

type file = {
  content : string;
  content_identity : Content_identity.t;
}

let ( let* ) = Result.bind

let close_noerr descriptor =
  try Unix.close descriptor with Unix.Unix_error _ -> ()

let protect operation f =
  try f () with
  | Unix.Unix_error _ | Sys_error _ | End_of_file ->
      Error (Filesystem_io operation)

let stable_stats left right =
  left.Unix.LargeFile.st_dev = right.Unix.LargeFile.st_dev
  && left.st_ino = right.st_ino
  && left.st_kind = right.st_kind
  && Int64.equal left.st_size right.st_size
  && Float.equal left.st_mtime right.st_mtime
  && Float.equal left.st_ctime right.st_ctime

let read_once descriptor =
  protect "read-artifact" (fun () ->
      ignore (Unix.LargeFile.lseek descriptor 0L Unix.SEEK_SET);
      let before = Unix.LargeFile.fstat descriptor in
      let buffer = Bytes.create 65536 in
      let output = Buffer.create 65536 in
      let rec loop digest byte_length =
        match Unix.read descriptor buffer 0 (Bytes.length buffer) with
        | 0 ->
            let after = Unix.LargeFile.fstat descriptor in
            if
              stable_stats before after
              && Int64.equal after.st_size (Int64.of_int byte_length)
            then
              let* content_identity =
                Content_identity.of_digest
                  ~digest:(Content_digest.Incremental.finish digest)
                  ~byte_length
                |> Result.map_error (fun _ ->
                       Filesystem_io "construct-content-identity")
              in
              Ok
                (Filesystem_stable_read.Stable
                   { content = Buffer.contents output; content_identity })
            else Ok Filesystem_stable_read.Changed
        | count ->
            if byte_length > Protocol_integer.maximum_safe - count then
              Error (Filesystem_io "artifact-size-limit")
            else (
              Buffer.add_subbytes output buffer 0 count;
              Content_digest.Incremental.feed_bytes digest buffer ~offset:0
                ~length:count
              |> fun digest -> loop digest (byte_length + count))
      in
      loop (Content_digest.Incremental.empty ()) 0)

let exact_entry directory segment =
  let* entries =
    protect "enumerate-parent" (fun () ->
        Ok (Filesystem_handle.entries directory))
  in
  if List.exists (String.equal segment) entries then Ok ()
  else
    try
      ignore (Filesystem_handle.entry_kind_at directory segment);
      Error (Unsafe Native_spelling_mismatch)
    with
    | Unix.Unix_error (Unix.ENOENT, _, _) -> Error Missing_artifact
    | Unix.Unix_error _ -> Error (Filesystem_io "inspect-path-component")

let entry_kind directory segment =
  protect "inspect-path-component" (fun () ->
      Ok (Filesystem_handle.entry_kind_at directory segment))

let open_directory directory segment =
  try Ok (Filesystem_handle.open_dir_at directory segment) with
  | Unix.Unix_error (Unix.ENOENT, _, _) -> Error Missing_artifact
  | Unix.Unix_error (Unix.ELOOP, _, _) -> Error (Unsafe Symlink_component)
  | Unix.Unix_error ((Unix.ENOTDIR | Unix.EINVAL), _, _) ->
      Error (Unsafe Parent_not_directory)
  | Unix.Unix_error _ -> Error (Filesystem_io "open-parent")

let open_regular directory segment =
  try Ok (Filesystem_handle.open_regular_at directory segment) with
  | Unix.Unix_error (Unix.ENOENT, _, _) -> Error Missing_artifact
  | Unix.Unix_error (Unix.ELOOP, _, _) ->
      Error (Unsafe (if Sys.win32 then Reparse_point else Symlink_component))
  | Unix.Unix_error ((Unix.EISDIR | Unix.EINVAL), _, _) ->
      Error (Unsafe Target_not_regular_file)
  | Unix.Unix_error _ -> Error (Filesystem_io "open-artifact")

let rec resolve current = function
  | [] -> invalid_arg "workspace path has no final segment"
  | [ final ] ->
      let* () = exact_entry current final in
      let* kind = entry_kind current final in
      (match kind with
      | Filesystem_handle.Regular_file -> open_regular current final
      | Filesystem_handle.Symlink -> Error (Unsafe Symlink_component)
      | Filesystem_handle.Reparse_point -> Error (Unsafe Reparse_point)
      | Filesystem_handle.Directory | Filesystem_handle.Other ->
          Error (Unsafe Target_not_regular_file))
  | segment :: rest ->
      let* () = exact_entry current segment in
      let* kind = entry_kind current segment in
      (match kind with
      | Filesystem_handle.Directory ->
          let* child = open_directory current segment in
          let result = resolve child rest in
          close_noerr child;
          result
      | Filesystem_handle.Symlink -> Error (Unsafe Symlink_component)
      | Filesystem_handle.Reparse_point -> Error (Unsafe Reparse_point)
      | Filesystem_handle.Regular_file | Filesystem_handle.Other ->
          Error (Unsafe Parent_not_directory))

let open_root workspace =
  try
    let root = Unix.realpath workspace in
    let stats = Unix.stat root in
    if stats.Unix.st_kind <> Unix.S_DIR then Error Invalid_workspace
    else Ok (Filesystem_handle.open_root root)
  with Unix.Unix_error _ | Sys_error _ -> Error Invalid_workspace

let read ~workspace ~path =
  let* root = open_root workspace in
  let opened = resolve root (Workspace_path.segments path) in
  close_noerr root;
  let* descriptor = opened in
  let result =
    Filesystem_stable_read.retry ~attempts:2 ~on_unstable:Unstable_content
      (fun () -> read_once descriptor)
  in
  close_noerr descriptor;
  result

let content file = file.content
let content_identity file = file.content_identity
