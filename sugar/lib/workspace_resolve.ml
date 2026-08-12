let command_result ?summary ?(diagnostics = []) ?(snapshots = [])
    ?(artifacts = []) ?(capabilities = []) ~termination () =
  match
    Command_result.make ~command:"resolve" ~termination
      ~effect:Command_result.No_change ~diagnostics ~snapshots ~artifacts
      ~capabilities ?summary ()
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

let diagnostic_result ?(capabilities = []) artifacts reference code message =
  let diagnostic =
    Diagnostic.make ~code ~message ~location:(reference_location reference) ()
    |> Result.get_ok
  in
  command_result ~termination:Command_result.Completed ~artifacts ~capabilities
    ~diagnostics:[ diagnostic ]
    ~summary:[ ("snapshots", Command_result.Count 0) ] ()

let find_reference inspected local =
  List.find_opt
    (fun reference ->
      String.equal local
        (Reference.id reference |> Reference_id.local |> Identifier.to_string))
    (Command_result.references inspected)

let snapshot_result ?(runtime_checked = false) ~artifacts ~capabilities
    ~reference ~artifact_identity ?region_fingerprint ?display ~observed_at () =
  let snapshot =
    Resolution_snapshot.make ~target:(Reference.target reference)
      ~artifact_identity ?region_fingerprint ?display ~observed_at ()
    |> Result.get_ok
  in
  let summary =
    [ ("snapshots", Command_result.Count 1) ]
    @
    if runtime_checked then [ ("runtimeChecked", Command_result.Flag true) ]
    else []
  in
  command_result ~termination:Command_result.Completed ~artifacts ~capabilities
    ~snapshots:[ snapshot ] ~summary ()

let inspected_failure inspected =
  match Command_result.termination inspected with
  | Command_result.Usage_failure message -> Some (usage message)
  | Command_result.Internal_failure _ -> Some (internal "inspect-artifact")
  | Command_result.Completed ->
      let diagnostics = Command_result.diagnostics inspected in
      if diagnostics = [] then None
      else
        Some
          (command_result ~termination:Command_result.Completed
             ~artifacts:(Command_result.artifacts inspected)
             ~capabilities:(Command_result.capabilities inspected) ~diagnostics
             ~summary:[ ("snapshots", Command_result.Count 0) ] ())

let resolve_reference ~workspace ~artifact ~reference:local ~observed_at =
  let inspected = Workspace_inspect.inspect ~workspace ~artifact in
  match inspected_failure inspected with
  | Some result -> result
  | None ->
      let artifacts = Command_result.artifacts inspected in
      let capabilities = Command_result.capabilities inspected in
      match find_reference inspected local with
      | None -> usage "reference is not declared by the selected artifact"
      | Some reference -> (
          match
            Reference_resolver.resolve ~workspace
              ~regions:(Command_result.regions inspected) reference
          with
          | Reference_resolver.Not_found ->
              diagnostic_result ~capabilities artifacts reference
                Diagnostic.Unresolved_ref
                ("reference " ^ local ^ " target does not resolve")
          | Reference_resolver.Read_failure ->
              diagnostic_result ~capabilities artifacts reference
                Diagnostic.Unresolved_ref
                ("reference " ^ local ^ " target cannot be read safely")
          | Reference_resolver.Invalid_selector message ->
              diagnostic_result ~capabilities artifacts reference
                Diagnostic.Invalid_selector message
          | Reference_resolver.Resolved resolved ->
              snapshot_result ~artifacts ~capabilities ~reference
                ~artifact_identity:resolved.artifact_identity
                ?region_fingerprint:resolved.region_fingerprint
                ?display:resolved.display ~observed_at ())

let extension_media_type descriptor =
  let capability = Extension_descriptor.capability descriptor in
  match Capability.applies_to capability with
  | Some { media_types = [ media_type ]; _ } -> Ok (Some media_type)
  | Some { media_types = []; _ } | None -> Ok None
  | Some { media_types; _ } ->
      Error
        (Printf.sprintf
           "extension resolve requires exactly one mediaTypes value or none, got %d"
           (List.length media_types))

let descriptor_interpreter descriptor =
  let capability = Extension_descriptor.capability descriptor in
  Interpreter.make ~name:(Capability.name capability)
    ~version:(Capability.version capability) ()
  |> Result.get_ok

let require_matching_target_interpreter descriptor reference =
  let expected = descriptor_interpreter descriptor in
  match
    Reference.target reference |> Region_address.interpreter_identity
  with
  | Some actual when Interpreter.equal expected actual -> Ok ()
  | Some actual ->
      Error
        (Printf.sprintf
           "selected reference requires interpreter %s@%s, but the extension descriptor provides %s@%s"
           (Interpreter.name actual) (Interpreter.version actual)
           (Interpreter.name expected) (Interpreter.version expected))
  | None ->
      Error "selected reference target does not declare an interpreter"

let require_matching_selector_schema descriptor selector =
  match selector with
  | Selector.Extension extension ->
      let capability = Extension_descriptor.capability descriptor in
      let declared =
        match Capability.schemas capability with
        | Some schemas -> schemas.selector
        | None -> None
      in
      let actual = Selector.Extension.schema extension in
      if declared = Some actual then Ok ()
      else
        Error
          "extension selector schema does not match the extension descriptor"
  | Selector.Whole_artifact
  | Selector.Region_id _
  | Selector.Text_range _
  | Selector.Row_filter _ ->
      Ok ()

let workspace_target reference =
  match Reference.target_artifact (Reference.target reference) with
  | Origin.Workspace path -> Ok path
  | _ -> Error "only workspace reference targets are supported"

let target_artifact ~media_type path file =
  let id =
    Artifact_id.make
      ("artifact:" ^ Workspace_path.to_canonical_string path)
    |> Result.get_ok
  in
  Artifact.make ~id ~origin:(Artifact.workspace path) ?media_type
    ~content_identity:(Workspace_read.content_identity file) ()
  |> Result.get_ok

let extension_failure_diagnostic ~capabilities artifacts reference failure =
  let code =
    if String.equal failure.Extension_observation.code "invalid-selector" then
      Diagnostic.Invalid_selector
    else Diagnostic.Unresolved_ref
  in
  let message =
    Printf.sprintf "extension resolveRegion %s: %s" failure.code failure.message
  in
  diagnostic_result ~capabilities artifacts reference code message

let resolve_with_extension_session ~workspace ~artifact ~reference:local
    ~observed_at ~descriptor ~session =
  let inspected =
    Workspace_inspect.inspect_with_extension_session ~workspace ~artifact
      ~descriptor ~session
  in
  match inspected_failure inspected with
  | Some result -> result
  | None ->
      let artifacts = Command_result.artifacts inspected in
      let capabilities = Command_result.capabilities inspected in
      match find_reference inspected local with
      | None -> usage "reference is not declared by the selected artifact"
      | Some reference ->
          match require_matching_target_interpreter descriptor reference with
          | Error message -> usage message
          | Ok () ->
              let selector =
                Reference.target_selector (Reference.target reference)
              in
              match require_matching_selector_schema descriptor selector with
              | Error message ->
                  diagnostic_result ~capabilities artifacts reference
                    Diagnostic.Invalid_selector message
              | Ok () ->
                  match workspace_target reference with
                  | Error message ->
                      diagnostic_result ~capabilities artifacts reference
                        Diagnostic.Invalid_selector message
                  | Ok path ->
                      match Workspace_read.read ~workspace ~path with
                      | Error Workspace_read.Missing_artifact ->
                          diagnostic_result ~capabilities artifacts reference
                            Diagnostic.Unresolved_ref
                            ("reference " ^ local ^ " target does not resolve")
                      | Error _ ->
                          diagnostic_result ~capabilities artifacts reference
                            Diagnostic.Unresolved_ref
                            ("reference " ^ local
                           ^ " target cannot be read safely")
                      | Ok file ->
                          let media_type =
                            extension_media_type descriptor |> Result.get_ok
                          in
                          let target_artifact =
                            target_artifact ~media_type path file
                          in
                          let params =
                            Extension_observation.resolve_params
                              ~artifact:target_artifact
                              ~content:(Workspace_read.content file) ~selector
                          in
                          match
                            Extension_runtime.call session
                              ~method_name:"monika.resolveRegion" ~params
                          with
                          | Error failure ->
                              usage
                                (Printf.sprintf "extension runtime %s: %s"
                                   (Extension_runtime.failure_code failure)
                                   (Extension_runtime.failure_message failure))
                          | Ok result ->
                              match
                                Extension_observation.decode_resolve_result
                                  ~descriptor ~target_artifact
                                  ~requested_selector:selector result
                              with
                              | Error message ->
                                  usage
                                    ("invalid extension region resolution: "
                                   ^ message)
                              | Ok
                                  (Extension_observation.Resolve_failure
                                    failure) ->
                                  extension_failure_diagnostic ~capabilities
                                    artifacts reference failure
                              | Ok
                                  (Extension_observation.Resolved_region region)
                                ->
                                  snapshot_result ~runtime_checked:true
                                    ~artifacts ~capabilities ~reference
                                    ~artifact_identity:
                                      (Artifact.content_identity target_artifact)
                                    ?region_fingerprint:
                                      (Region.fingerprint region)
                                    ?display:(Region.summary region) ~observed_at
                                    ()

let resolve_reference_with_extension ~workspace ~artifact ~reference
    ~observed_at ~descriptor ~executable ~arguments =
  let capability = Extension_descriptor.capability descriptor in
  if Capability.kind capability <> Capability.Interpreter then
    usage "extension resolve requires an interpreter capability"
  else
    match extension_media_type descriptor with
    | Error message -> usage message
    | Ok _ -> (
        match
          Extension_runtime.with_checked_session ~executable ~arguments
            ~limits:Extension_runtime.default_limits ~descriptor (fun session ->
              Ok
                (resolve_with_extension_session ~workspace ~artifact ~reference
                   ~observed_at ~descriptor ~session))
        with
        | Ok result -> result
        | Error failure ->
            usage
              (Printf.sprintf "extension runtime %s: %s"
                 (Extension_runtime.failure_code failure)
                 (Extension_runtime.failure_message failure)))
