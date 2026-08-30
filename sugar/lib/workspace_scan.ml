type candidate = {
  path : Workspace_path.t;
  content : string;
}

type scan_state = {
  candidates : candidate list;
  sidecar_candidates : candidate list;
  diagnostics : Diagnostic.t list;
  primary_discovered : int;
  primary_failed : int;
  metadata_discovered : int;
  metadata_failures : Metadata_failure.t list;
}

module String_map = Map.Make (String)

let command_result ?summary ?(diagnostics = []) ?(observations = [])
    ?(sidecar_snapshots = []) ?(coverage = Coverage.empty) ~termination () =
  match
    Command_result.make ~command:"scan" ~termination
      ~effect:Command_result.No_change ~diagnostics ~observations
      ~sidecar_snapshots ~coverage ?summary ()
  with
  | Ok result -> result
  | Error _ ->
      Command_result.internal_error ~command:"scan"
        ~error_code:"internal-invariant" ~operation:"construct-command-result"

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

let with_descriptor opened operation =
  match opened with
  | Error message -> Error message
  | Ok descriptor ->
      Fun.protect ~finally:(fun () -> close_noerr descriptor) (fun () ->
          operation descriptor)

let stable_stats left right =
  left.Unix.LargeFile.st_dev = right.Unix.LargeFile.st_dev
  && left.st_ino = right.st_ino
  && left.st_kind = right.st_kind
  && Int64.equal left.st_size right.st_size
  && Float.equal left.st_mtime right.st_mtime
  && Float.equal left.st_ctime right.st_ctime

let read_descriptor ~capture_content descriptor =
  protect (fun () ->
      let before = Unix.LargeFile.fstat descriptor in
      let buffer = Bytes.create 65536 in
      let content = if capture_content then Some (Buffer.create 4096) else None in
      let rec loop digest byte_length =
        let read_length = Unix.read descriptor buffer 0 (Bytes.length buffer) in
        if read_length = 0 then
          let after = Unix.LargeFile.fstat descriptor in
          if
            stable_stats before after
            && Int64.equal after.st_size (Int64.of_int byte_length)
          then
            Result.map
              (fun identity ->
                let content = Option.map Buffer.contents content in
                `Stable (identity, content))
              (Content_identity.of_digest
                 ~digest:(Content_digest.Incremental.finish digest)
                 ~byte_length)
          else Ok `Changed
        else if byte_length > max_int - read_length then
          Error "observation size exceeds the supported integer range"
        else (
          Option.iter
            (fun output -> Buffer.add_subbytes output buffer 0 read_length)
            content;
          Result.bind
            (Content_digest.Incremental.feed_bytes digest buffer ~offset:0
               ~length:read_length)
            (fun digest -> loop digest (byte_length + read_length)))
      in
      loop (Content_digest.Incremental.empty ()) 0)

let read_descriptor_content descriptor =
  Result.bind
    (read_descriptor ~capture_content:true descriptor)
    (function
      | `Stable (_, Some content) -> Ok (`Stable content)
      | `Stable (_, None) ->
          Error "stable observation read did not retain its bytes"
      | `Changed -> Ok `Changed)

let observation_id path =
  Observation_id.make
    ("observation:" ^ Workspace_path.to_canonical_string path)

let unsupported path message =
  match observation_id path with
  | Error error -> Error error
  | Ok id ->
      Diagnostic.make ~code:Diagnostic.Unsupported_filesystem_entry ~message
        ~location:
          {
            Diagnostic.observation = Some id;
            region = None;
            annotation = None;
            range = None;
          }
        ()

let observation ~classify { path; content } =
  Result.bind (observation_id path) (fun id ->
      Result.bind (classify path) (fun observation_type ->
      let origin = Observation.workspace path in
      Ok
        (Observation.of_bytes ~id ~origin ~observation_type ~bytes:content)))

let observations ~classify candidates =
  List.fold_right
    (fun candidate result ->
      Result.bind (observation ~classify candidate) (fun observation ->
          Result.map (fun observations -> observation :: observations) result))
    candidates (Ok [])

let workspace_path reversed_segments =
  Workspace_path.of_segments (List.rev reversed_segments)

let posix_read_content path parent name =
  Filesystem_stable_read.retry ~attempts:Filesystem_stable_read.twice
    ~on_unstable:
      (Workspace_path.to_canonical_string path
     ^ ": file changed while its observation was being fixed")
    (fun () ->
      with_descriptor
        (protect (fun () ->
             Ok (Filesystem_handle.open_regular_at parent name)))
        (fun descriptor ->
          match read_descriptor_content descriptor with
          | Ok (`Stable content) ->
              Ok (Filesystem_stable_read.Stable content)
          | Ok `Changed -> Ok Filesystem_stable_read.Changed
          | Error message -> Error message))

let posix_read_ignore path parent name =
  Filesystem_stable_read.retry ~attempts:Filesystem_stable_read.twice
    ~on_unstable:
      (Workspace_path.to_canonical_string path
     ^ ": file changed while its ignore patterns were being read")
    (fun () ->
      with_descriptor
        (protect (fun () ->
             Ok (Filesystem_handle.open_regular_at parent name)))
        (fun descriptor ->
          match read_descriptor ~capture_content:true descriptor with
          | Ok (`Stable (identity, Some content)) ->
              Ok (Filesystem_stable_read.Stable (identity, content))
          | Ok (`Stable (_, None)) ->
              Error "ignore pattern content was not retained"
          | Ok `Changed -> Ok Filesystem_stable_read.Changed
          | Error message -> Error message))

let ignore_base reversed_segments =
  match List.rev reversed_segments with
  | [] -> Ok None
  | segments -> Workspace_path.of_segments segments |> Result.map Option.some

let load_ignore_rules reversed_segments directory entries inherited =
  let ignore_files = [ ".gitignore"; ".monikaignore" ] in
  Result.bind (ignore_base reversed_segments) (fun base ->
      List.fold_left
        (fun result name ->
          Result.bind result (fun (rules, identities) ->
              if not (List.mem name entries) then Ok (rules, identities)
              else
                Result.bind
                  (protect (fun () ->
                       Ok (Filesystem_handle.entry_kind_at directory name)))
                  (function
                    | Filesystem_handle.Regular_file ->
                        Result.bind
                          (workspace_path (name :: reversed_segments))
                          (fun path ->
                            Result.map
                              (fun (_identity, content) ->
                                ( Workspace_ignore.add_patterns ~base content
                                    rules,
                                  String_map.add name content identities ))
                              (posix_read_ignore path directory name))
                    | Filesystem_handle.Directory
                    | Filesystem_handle.Symlink
                    | Filesystem_handle.Reparse_point
                    | Filesystem_handle.Other ->
                        Ok (rules, identities))))
        (Ok (inherited, String_map.empty)) ignore_files)

let is_vcs_metadata entry = String.equal entry ".git"

let directory_entry = function
  | Filesystem_handle.Directory -> true
  | Filesystem_handle.Regular_file
  | Filesystem_handle.Symlink
  | Filesystem_handle.Reparse_point
  | Filesystem_handle.Other ->
      false

let is_sidecar_path path =
  match List.rev (Workspace_path.segments path) with
  | name :: _ -> String.ends_with ~suffix:".annotations.yaml" name
  | [] -> false

let add_candidate state path content =
  if is_sidecar_path path then
    {
      state with
      sidecar_candidates = { path; content } :: state.sidecar_candidates;
      metadata_discovered = state.metadata_discovered + 1;
    }
  else
    {
      state with
      candidates = { path; content } :: state.candidates;
      primary_discovered = state.primary_discovered + 1;
    }

let add_read_failure state path message =
  if is_sidecar_path path then
    Result.bind
      (Metadata_failure.make ~path ~operation:Metadata_failure.Read
         ~code:"filesystem-io" ~message ())
      (fun failure ->
        Ok
          {
            state with
            metadata_discovered = state.metadata_discovered + 1;
            metadata_failures = failure :: state.metadata_failures;
          })
  else
    Result.bind (observation_id path) (fun observation ->
        Result.map
          (fun diagnostic ->
            {
              state with
              primary_discovered = state.primary_discovered + 1;
              primary_failed = state.primary_failed + 1;
              diagnostics = diagnostic :: state.diagnostics;
            })
          (Diagnostic.make ~code:Diagnostic.Observation_failure
             ~message:
               (Workspace_path.to_canonical_string path
              ^ ": resource observation failed [filesystem-io]: " ^ message)
             ~location:
               {
                 Diagnostic.observation = Some observation;
                 region = None;
                 annotation = None;
                 range = None;
               }
             ()))

let record_candidate state path = function
  | Ok content -> Ok (add_candidate state path content)
  | Error message -> add_read_failure state path message

let add_unsupported state path message =
  Result.map
    (fun diagnostic ->
      { state with diagnostics = diagnostic :: state.diagnostics })
    (unsupported path message)

let rec scan_posix_path reversed_segments directory rules state =
  Result.bind
    (protect (fun () -> Ok (Filesystem_handle.entries directory)))
    (fun entries ->
      Result.bind
        (load_ignore_rules reversed_segments directory entries rules)
        (fun (rules, preloaded_identities) ->
          List.fold_left
            (fun result entry ->
              Result.bind result
                (scan_posix_entry reversed_segments directory rules
                   preloaded_identities entry))
            (Ok state) entries))

and scan_posix_entry reversed_segments directory rules preloaded_identities
    entry state =
  Result.bind
    (workspace_path (entry :: reversed_segments))
    (fun path ->
      let preloaded_content =
        String_map.find_opt entry preloaded_identities
      in
      let kind =
        match preloaded_content with
        | Some _ -> Ok Filesystem_handle.Regular_file
        | None ->
            protect (fun () ->
                Ok (Filesystem_handle.entry_kind_at directory entry))
      in
      Result.bind
        kind
        (fun kind ->
          if
            is_vcs_metadata entry
            || Workspace_ignore.is_ignored rules ~path
                 ~directory:(directory_entry kind)
          then Ok state
          else
            match kind with
            | Filesystem_handle.Directory ->
                with_descriptor
                  (protect (fun () ->
                       Ok (Filesystem_handle.open_dir_at directory entry)))
                  (fun child ->
                    scan_posix_path (entry :: reversed_segments) child rules
                      state)
            | Filesystem_handle.Regular_file ->
                let content =
                  match preloaded_content with
                  | Some content -> Ok content
                  | None -> posix_read_content path directory entry
                in
                record_candidate state path content
            | Filesystem_handle.Symlink ->
                add_unsupported state path "symbolic links are not scanned"
            | Filesystem_handle.Reparse_point ->
                add_unsupported state path "reparse points are not scanned"
            | Filesystem_handle.Other ->
                add_unsupported state path
                  "unsupported filesystem entry type"))

let scan_posix root =
  with_descriptor
    (protect (fun () -> Ok (Filesystem_handle.open_root root)))
    (fun descriptor ->
      scan_posix_path [] descriptor Workspace_ignore.empty
        {
          candidates = [];
          sidecar_candidates = [];
          diagnostics = [];
          primary_discovered = 0;
          primary_failed = 0;
          metadata_discovered = 0;
          metadata_failures = [];
        })

let sidecar_snapshots candidates =
  List.map
    (fun candidate -> Sidecar_snapshot.of_bytes ~path:candidate.path candidate.content)
    candidates
  |> List.sort Sidecar_snapshot.compare

let decode_sidecars snapshots =
  List.fold_left
    (fun result snapshot ->
      Result.bind result (fun (decoded, failures) ->
      match Sidecar_v2.decode snapshot with
      | Ok _ -> Ok (decoded + 1, failures)
      | Error message ->
          Result.map
            (fun failure -> (decoded, failure :: failures))
            (Metadata_failure.make ~path:(Sidecar_snapshot.path snapshot)
               ~content_identity:(Sidecar_snapshot.content_identity snapshot)
               ~operation:Metadata_failure.Decode ~code:"invalid-sidecar"
               ~message ())))
    (Ok (0, [])) snapshots

let metadata_diagnostics failures =
  List.fold_right
    (fun failure result ->
      Result.bind (Metadata_failure.to_diagnostic failure) (fun diagnostic ->
          Result.map (fun diagnostics -> diagnostic :: diagnostics) result))
    failures (Ok [])

let resolve_root workspace =
  protect (fun () ->
      let root = Unix.realpath workspace in
      let stat = Unix.stat root in
      if stat.Unix.st_kind = Unix.S_DIR then Ok root
      else Error "workspace must be a directory")

let scan_with_classifier ~workspace ~classify =
  match resolve_root workspace with
  | Error message -> invalid_input message
  | Ok root -> (
      match
        scan_posix root
      with
      | Error message -> internal_error message
      | Ok state -> (
          match observations ~classify state.candidates with
          | Error message -> invalid_input message
          | Ok observations ->
              let sidecar_snapshots = sidecar_snapshots state.sidecar_candidates in
              (match decode_sidecars sidecar_snapshots with
              | Error message -> internal_error message
              | Ok (metadata_decoded, decode_failures) ->
                  let metadata_failures =
                    List.rev_append decode_failures state.metadata_failures
                  in
                  (match metadata_diagnostics metadata_failures with
                  | Error message -> internal_error message
                  | Ok metadata_diagnostics ->
                      let diagnostics =
                        List.rev_append metadata_diagnostics state.diagnostics
                      in
                      let metadata_discovered = state.metadata_discovered in
                      let metadata_failed = List.length metadata_failures in
                      let coverage =
                        Coverage.make
                          ~primary_resources:state.primary_discovered
                          ~observed:(List.length observations) ~interpreted:0
                          ~unsupported:0 ~failed:state.primary_failed
                          ~metadata_discovered ~metadata_decoded ~metadata_failed
                          ~complete:
                            (state.primary_failed = 0 && metadata_failed = 0)
                      in
                      (match coverage with
                      | Error message -> internal_error message
                      | Ok coverage ->
                          command_result ~termination:Command_result.Completed
                            ~diagnostics ~observations ~sidecar_snapshots ~coverage
                            ~summary:
                              [
                                ( "observationCount",
                                  Command_result.Count
                                    (List.length observations) );
                                ( "diagnosticCount",
                                  Command_result.Count
                                    (List.length diagnostics) );
                                ( "metadataCount",
                                  Command_result.Count metadata_discovered );
                              ]
                            ())))))

let scan ~workspace =
  scan_with_classifier ~workspace
    ~classify:(fun path -> Ok (Workspace_observation_type.classify path))
