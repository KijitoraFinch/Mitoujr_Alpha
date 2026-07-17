type scan_state = {
  artifacts : Artifact.t list;
  diagnostics : Diagnostic.t list;
}

let command_result ?summary ?(diagnostics = []) ?(artifacts = [])
    ~termination () =
  match
    Command_result.make ~command:"scan" ~termination
      ~effect:Command_result.No_change ~diagnostics ~artifacts ?summary ()
  with
  | Ok result -> result
  | Error message -> invalid_arg ("invalid scan CommandResult: " ^ message)

let invalid_input message =
  command_result ~termination:(Command_result.Usage_failure message)
    ~summary:[ ("message", Command_result.Text message) ] ()

let internal_error message =
  command_result ~termination:(Command_result.Internal_failure message)
    ~summary:[ ("message", Command_result.Text message) ] ()

let unix_error_message error function_name argument =
  let message = Unix.error_message error in
  if String.length argument = 0 then function_name ^ ": " ^ message
  else function_name ^ "(" ^ argument ^ "): " ^ message

let protect operation =
  try operation () with
  | Unix.Unix_error (error, function_name, argument) ->
      Error (unix_error_message error function_name argument)
  | Sys_error message -> Error message
  | End_of_file -> Error "unexpected end of file"

let close_noerr descriptor = try Unix.close descriptor with Unix.Unix_error _ -> ()

let stable_stats left right =
  left.Unix.LargeFile.st_dev = right.Unix.LargeFile.st_dev
  && left.st_ino = right.st_ino
  && left.st_kind = right.st_kind
  && Int64.equal left.st_size right.st_size
  && Float.equal left.st_mtime right.st_mtime
  && Float.equal left.st_ctime right.st_ctime

let read_descriptor_identity descriptor =
  protect (fun () ->
      let before = Unix.LargeFile.fstat descriptor in
      let buffer = Bytes.create 65536 in
      let rec loop digest byte_length =
        let read_length = Unix.read descriptor buffer 0 (Bytes.length buffer) in
        if read_length = 0 then
          let after = Unix.LargeFile.fstat descriptor in
          if
            stable_stats before after
            && Int64.equal after.st_size (Int64.of_int byte_length)
          then
            Content_identity.of_digest
              ~digest:(Content_digest.Incremental.finish digest)
              ~byte_length
            |> Result.map (fun identity -> `Stable identity)
          else Ok `Changed
        else if byte_length > max_int - read_length then
          Error "artifact size exceeds the supported integer range"
        else
          Content_digest.Incremental.feed_bytes digest buffer ~offset:0
            ~length:read_length
          |> fun digest -> loop digest (byte_length + read_length)
      in
      loop (Content_digest.Incremental.empty ()) 0)

let artifact_id path =
  Artifact_id.make
    ("artifact:" ^ Workspace_path.to_canonical_string path)

let unsupported path message =
  match artifact_id path with
  | Error error -> Error error
  | Ok id ->
      Diagnostic.make ~code:Diagnostic.Unsupported_filesystem_entry ~message
        ~location:
          {
            Diagnostic.artifact = Some id;
            region = None;
            annotation = None;
            range = None;
          }
        ()

let artifact path content_identity =
  Result.bind (artifact_id path) (fun id ->
      let origin = Artifact.workspace path in
      Artifact.make ~id ~origin ~content_identity ())

let workspace_path reversed_segments =
  Workspace_path.of_segments (List.rev reversed_segments)

let posix_read_identity path parent name =
  Filesystem_stable_read.retry ~attempts:2
    ~on_unstable:
      (Workspace_path.to_canonical_string path
     ^ ": file changed while its content identity was being computed")
    (fun () ->
      let opened =
        protect (fun () ->
            Ok (Filesystem_handle.open_regular_at parent name))
      in
      match opened with
      | Error message -> Error message
      | Ok descriptor ->
          let result = read_descriptor_identity descriptor in
          close_noerr descriptor;
          (match result with
          | Ok (`Stable identity) ->
              Ok (Filesystem_stable_read.Stable identity)
          | Ok `Changed -> Ok Filesystem_stable_read.Changed
          | Error message -> Error message))

let rec scan_posix_path reversed_segments directory state =
  Result.bind
    (protect (fun () -> Ok (Filesystem_handle.entries directory)))
    (fun entries ->
      List.fold_left
        (fun result entry ->
          Result.bind result (fun state ->
              Result.bind
                (workspace_path (entry :: reversed_segments))
                (fun path ->
                  Result.bind
                    (protect (fun () ->
                         Ok (Filesystem_handle.entry_kind_at directory entry)))
                    (function
                      | Filesystem_handle.Directory ->
                          let opened =
                            protect (fun () ->
                                Ok
                                  (Filesystem_handle.open_dir_at directory entry))
                          in
                          Result.bind opened (fun child ->
                              let result =
                                scan_posix_path (entry :: reversed_segments)
                                  child state
                              in
                              close_noerr child;
                              result)
                      | Filesystem_handle.Regular_file ->
                          Result.bind
                            (posix_read_identity path directory entry)
                            (fun content_identity ->
                              Result.map
                                (fun value ->
                                  {
                                    state with
                                    artifacts = value :: state.artifacts;
                                  })
                                (artifact path content_identity))
                      | Filesystem_handle.Symlink ->
                          Result.map
                            (fun diagnostic ->
                              {
                                state with
                                diagnostics = diagnostic :: state.diagnostics;
                              })
                            (unsupported path "symbolic links are not scanned")
                      | Filesystem_handle.Reparse_point ->
                          Result.map
                            (fun diagnostic ->
                              {
                                state with
                                diagnostics = diagnostic :: state.diagnostics;
                              })
                            (unsupported path "reparse points are not scanned")
                      | Filesystem_handle.Other ->
                          Result.map
                            (fun diagnostic ->
                              {
                                state with
                                diagnostics = diagnostic :: state.diagnostics;
                              })
                            (unsupported path
                               "unsupported filesystem entry type")))))
        (Ok state) entries)

let scan_posix root =
  match protect (fun () -> Ok (Filesystem_handle.open_root root)) with
  | Error message -> Error message
  | Ok descriptor ->
      let result =
        scan_posix_path [] descriptor { artifacts = []; diagnostics = [] }
      in
      close_noerr descriptor;
      result

let resolve_root workspace =
  protect (fun () ->
      let root = Unix.realpath workspace in
      let stat = Unix.stat root in
      if stat.Unix.st_kind = Unix.S_DIR then Ok root
      else Error "workspace must be a directory")

let scan ~workspace =
  match resolve_root workspace with
  | Error message -> invalid_input message
  | Ok root -> (
      match
        scan_posix root
      with
      | Error message -> internal_error message
      | Ok state ->
          command_result ~termination:Command_result.Completed
            ~diagnostics:state.diagnostics ~artifacts:state.artifacts
            ~summary:
              [
                ("artifactCount", Command_result.Count (List.length state.artifacts));
                ( "diagnosticCount",
                  Command_result.Count (List.length state.diagnostics) );
              ]
            ())
