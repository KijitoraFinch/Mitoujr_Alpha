let command_result ?summary ?(diagnostics = []) ?(snapshots = [])
    ?(artifacts = []) ~termination () =
  match
    Command_result.make ~command:"resolve" ~termination
      ~effect:Command_result.No_change ~diagnostics ~snapshots ~artifacts
      ?summary ()
  with
  | Ok result -> result
  | Error message -> invalid_arg ("invalid resolve CommandResult: " ^ message)

let usage message =
  command_result ~termination:(Command_result.Usage_failure message)
    ~summary:[ ("message", Command_result.Text message) ] ()

let internal operation =
  command_result
    ~termination:(Command_result.Internal_failure "internal operation failed")
    ~summary:
      [
        ("errorCode", Command_result.Text "filesystem-io");
        ("operation", Command_result.Text operation);
      ]
    ()

let canonical_observed_at value =
  match Ptime.of_rfc3339 value with
  | Error _ -> Error "--observed-at must be a canonical RFC 3339 UTC timestamp"
  | Ok (time, _, _) ->
      let canonical = Ptime.to_rfc3339 ~tz_offset_s:0 time in
      if String.equal value canonical then Ok canonical
      else Error "--observed-at must be a canonical RFC 3339 UTC timestamp"

let reference_location reference =
  let id = Reference.id reference in
  {
    Diagnostic.artifact = Some (Reference_id.artifact id);
    region = None;
    annotation = None;
    range = None;
  }

let diagnostic_result artifacts reference code message =
  let diagnostic =
    Diagnostic.make ~code ~message ~location:(reference_location reference) ()
    |> Result.get_ok
  in
  command_result ~termination:Command_result.Completed ~artifacts
    ~diagnostics:[ diagnostic ]
    ~summary:[ ("snapshots", Command_result.Count 0) ] ()

let resolve_reference ~workspace ~artifact ~reference:local ~observed_at =
  let inspected = Workspace_inspect.inspect ~workspace ~artifact in
  match Command_result.termination inspected with
  | Command_result.Usage_failure message -> usage message
  | Command_result.Internal_failure _ -> internal "inspect-artifact"
  | Command_result.Completed ->
      let artifacts = Command_result.artifacts inspected in
      if Command_result.diagnostics inspected <> [] then
        command_result ~termination:Command_result.Completed ~artifacts
          ~diagnostics:(Command_result.diagnostics inspected)
          ~summary:[ ("snapshots", Command_result.Count 0) ] ()
      else
        let reference =
          List.find_opt
            (fun reference ->
              String.equal local
                (Reference.id reference |> Reference_id.local
               |> Identifier.to_string))
            (Command_result.references inspected)
        in
        match reference with
        | None -> usage "reference is not declared by the selected artifact"
        | Some reference -> (
            match
              Reference_resolver.resolve ~workspace
                ~regions:(Command_result.regions inspected) reference
            with
            | Reference_resolver.Not_found ->
                diagnostic_result artifacts reference Diagnostic.Unresolved_ref
                  ("reference " ^ local ^ " target does not resolve")
            | Reference_resolver.Read_failure ->
                diagnostic_result artifacts reference Diagnostic.Unresolved_ref
                  ("reference " ^ local ^ " target cannot be read safely")
            | Reference_resolver.Invalid_selector message ->
                diagnostic_result artifacts reference Diagnostic.Invalid_selector
                  message
            | Reference_resolver.Resolved resolved ->
                let snapshot =
                  Resolution_snapshot.make ~target:(Reference.target reference)
                    ~artifact_identity:resolved.artifact_identity
                    ?region_fingerprint:resolved.region_fingerprint
                    ?display:resolved.display ~observed_at ()
                  |> Result.get_ok
                in
                command_result ~termination:Command_result.Completed ~artifacts
                  ~snapshots:[ snapshot ]
                  ~summary:[ ("snapshots", Command_result.Count 1) ] ())
