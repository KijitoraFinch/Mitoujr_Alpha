let command_result ?summary ?(diagnostics = []) ?(snapshots = [])
    ?(observations = []) ?(capabilities = []) ~termination () =
  match
    Command_result.make ~command:"resolve" ~termination
      ~effect:Command_result.No_change ~diagnostics ~snapshots ~observations
      ~capabilities ?summary ()
  with
  | Ok result -> result
  | Error _ ->
      Command_result.internal_error ~command:"resolve"
        ~error_code:"internal-invariant" ~operation:"construct-command-result"

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
    Diagnostic.observation = Some (Reference_id.observation id);
    region = None;
    annotation = None;
    range = None;
  }

let diagnostic_result ?(capabilities = []) ?extension_failure observations
    reference code message =
  match
    Diagnostic.make ~code ~message ~location:(reference_location reference)
      ?extension_failure ()
  with
  | Error _ -> internal "construct-diagnostic"
  | Ok diagnostic ->
      command_result ~termination:Command_result.Completed ~observations
        ~capabilities ~diagnostics:[ diagnostic ]
        ~summary:[ ("snapshots", Command_result.Count 0) ] ()

let extension_session_failure_result manifest failure =
  match
    Diagnostic.make ~code:Diagnostic.Extension_failure
      ~message:(Extension_failure.message failure)
      ~extension_failure:failure ()
  with
  | Error _ -> internal "construct-extension-session-failure-diagnostic"
  | Ok diagnostic ->
      command_result ~termination:Command_result.Completed
        ~capabilities:[ Extension_manifest.capability manifest ]
        ~diagnostics:[ diagnostic ]
        ~summary:[ ("snapshots", Command_result.Count 0) ] ()

let runtime_extension_failure operation failure =
  Extension_failure.make ~operation
    ~code:(Extension_runtime.failure_code failure)
    ~message:(Extension_runtime.failure_message failure)
    ?data:(Extension_runtime.failure_data failure) ()

let find_reference inspected local =
  List.find_opt
    (fun reference ->
      String.equal local
        (Reference.id reference |> Reference_id.local |> Identifier.to_string))
    (Command_result.references inspected)

let snapshot_result ?(runtime_checked = false) ~observations ~capabilities
    ~reference ~observation_identity ?region_fingerprint ?display ~observed_at () =
  match
    Resolution_snapshot.make ~target:(Reference.target reference)
      ~observation_identity ?region_fingerprint ?display ~observed_at ()
  with
  | Error _ -> internal "construct-resolution-snapshot"
  | Ok snapshot ->
      let summary =
        [ ("snapshots", Command_result.Count 1) ]
        @
        if runtime_checked then [ ("runtimeChecked", Command_result.Flag true) ]
        else []
      in
      command_result ~termination:Command_result.Completed ~observations
        ~capabilities ~snapshots:[ snapshot ] ~summary ()

let inspected_failure inspected =
  match Command_result.termination inspected with
  | Command_result.Usage_failure message -> Some (usage message)
  | Command_result.Internal_failure _ -> Some (internal "inspect-observation")
  | Command_result.Completed ->
      let diagnostics = Command_result.diagnostics inspected in
      if diagnostics = [] then None
      else
        Some
          (command_result ~termination:Command_result.Completed
             ~observations:(Command_result.observations inspected)
             ~capabilities:(Command_result.capabilities inspected) ~diagnostics
             ~summary:[ ("snapshots", Command_result.Count 0) ] ())

let resolve_reference ~workspace ~observation ~reference:local ~observed_at =
  let inspected = Workspace_inspect.inspect ~workspace ~observation in
  match inspected_failure inspected with
  | Some result -> result
  | None ->
      let observations = Command_result.observations inspected in
      let capabilities = Command_result.capabilities inspected in
      match find_reference inspected local with
      | None -> usage "reference is not declared by the selected observation"
      | Some reference -> (
          match
            Reference_resolver.resolve ~workspace
              ~regions:(Command_result.regions inspected) reference
          with
          | Reference_resolver.Not_found ->
              diagnostic_result ~capabilities observations reference
                Diagnostic.Unresolved_ref
                ("reference " ^ local ^ " target does not resolve")
          | Reference_resolver.Read_failure ->
              diagnostic_result ~capabilities observations reference
                Diagnostic.Unresolved_ref
                ("reference " ^ local ^ " target cannot be read safely")
          | Reference_resolver.Invalid_selector message ->
              diagnostic_result ~capabilities observations reference
                Diagnostic.Invalid_selector message
          | Reference_resolver.Resolved resolved ->
              snapshot_result ~observations ~capabilities ~reference
                ~observation_identity:resolved.observation_identity
                ?region_fingerprint:resolved.region_fingerprint
                ?display:resolved.display ~observed_at ())

let extension_associated_observation_type manifest path =
  let capability = Extension_manifest.capability manifest in
  match Extension_applicability.associate capability ~path with
  | Error _ as error -> error
  | Ok Extension_applicability.Not_associated ->
      Error "extension does not apply to the selected observation"
  | Ok (Extension_applicability.Associated observation_type) ->
      Ok observation_type

let require_matching_selector_schema manifest selector =
  match selector with
  | Selector.Extension extension ->
      let capability = Extension_manifest.capability manifest in
      let declared =
        match Capability.schemas capability with
        | Some schemas -> schemas.selector
        | None -> None
      in
      let actual = Selector.Extension.schema extension in
      if declared = Some actual then Ok ()
      else
        Error
          "extension selector schema does not match the extension manifest"
  | Selector.Whole_observation
  | Selector.Region_id _
  | Selector.Text_range _
  | Selector.Row_filter _ ->
      Ok ()

let workspace_target reference =
  match Reference.target_origin (Reference.target reference) with
  | Origin.Workspace path -> Ok path
  | _ -> Error "only workspace reference targets are supported"

let target_observation ~observation_type path file =
  let ( let* ) = Result.bind in
  let* id =
    Observation_id.make
      ("observation:" ^ Workspace_path.to_canonical_string path)
  in
  Ok
    (Observation.of_content ~id ~origin:(Observation.workspace path)
       ~observation_type ~content_identity:(Workspace_read.content_identity file))

let extension_failure_diagnostic ~capabilities observations reference failure =
  let code =
    if
      String.equal (Extension_failure.code failure) "invalid-selector"
    then
      Diagnostic.Invalid_selector
    else Diagnostic.Unresolved_ref
  in
  diagnostic_result ~capabilities ~extension_failure:failure observations
    reference code (Extension_failure.message failure)

let add_capability capabilities capability =
  if List.exists (fun candidate -> Capability.compare candidate capability = 0) capabilities
  then capabilities
  else capability :: capabilities

let resolve_with_installed_interpreter ~workspace ~local ~observed_at
    ~observations ~capabilities ~reference ~extension =
  let manifest = Installed_extension.manifest extension in
  let capability = Installed_extension.capability extension in
  let capabilities = add_capability capabilities capability in
  let selector = Reference.target_selector (Reference.target reference) in
  match require_matching_selector_schema manifest selector with
  | Error message ->
      diagnostic_result ~capabilities observations reference
        Diagnostic.Invalid_selector message
  | Ok () -> (
      match workspace_target reference with
      | Error message ->
          diagnostic_result ~capabilities observations reference
            Diagnostic.Invalid_selector message
      | Ok path -> (
          match Workspace_read.read ~workspace ~path with
          | Error Workspace_read.Missing_file ->
              diagnostic_result ~capabilities observations reference
                Diagnostic.Unresolved_ref
                ("reference " ^ local ^ " target does not resolve")
          | Error _ ->
              diagnostic_result ~capabilities observations reference
                Diagnostic.Unresolved_ref
                ("reference " ^ local ^ " target cannot be read safely")
          | Ok file -> (
              match extension_associated_observation_type manifest path with
              | Error message ->
                  diagnostic_result ~capabilities observations reference
                    Diagnostic.Invalid_selector message
              | Ok observation_type -> (
                  match target_observation ~observation_type path file with
                  | Error _ -> internal "construct-target-observation"
                  | Ok target_observation ->
                      let params =
                        Extension_interpreter_protocol.resolve_params
                          ~observation:target_observation ~selector
                      in
                      match
                        Extension_runtime.with_checked_session
                          ~executable:(Installed_extension.executable extension)
                          ~arguments:(Installed_extension.arguments extension)
                          ~limits:Extension_runtime.default_limits ~manifest
                          (fun session ->
                            match
                              Extension_runtime.call_with_content session
                                ~method_name:"monika.resolveRegion" ~params
                                ~content:(Workspace_read.content file)
                            with
                            | Ok result -> Ok (`Result result)
                            | Error failure -> Ok (`Method_failure failure))
                      with
                      | Error runtime_failure -> (
                          match
                            runtime_extension_failure Extension_failure.Session
                              runtime_failure
                          with
                          | Error _ ->
                              internal "construct-extension-session-failure"
                          | Ok failure ->
                              diagnostic_result ~capabilities
                                ~extension_failure:failure observations reference
                                Diagnostic.Extension_failure
                                (Extension_failure.message failure))
                      | Ok (`Method_failure runtime_failure) -> (
                          match
                            runtime_extension_failure
                              Extension_failure.Resolve_region runtime_failure
                          with
                          | Error _ ->
                              internal "construct-extension-runtime-failure"
                          | Ok failure ->
                              diagnostic_result ~capabilities
                                ~extension_failure:failure observations reference
                                Diagnostic.Extension_failure
                                (Extension_failure.message failure))
                      | Ok (`Result result) -> (
                          match
                            Extension_interpreter_protocol.decode_resolve_result
                              ~manifest ~target_observation
                              ~requested_selector:selector result
                          with
                          | Error message -> (
                              match
                                Extension_failure.make
                                  ~operation:Extension_failure.Resolve_region
                                  ~code:"invalid-result" ~message ()
                              with
                              | Error _ ->
                                  internal "construct-invalid-extension-result"
                              | Ok failure ->
                                  diagnostic_result ~capabilities
                                    ~extension_failure:failure observations
                                    reference Diagnostic.Extension_failure
                                    (Extension_failure.message failure))
                          | Ok
                              (Extension_interpreter_protocol.Resolve_failure
                                failure) ->
                              extension_failure_diagnostic ~capabilities
                                observations reference failure
                          | Ok
                              (Extension_interpreter_protocol.Resolved_region
                                region) ->
                              snapshot_result ~runtime_checked:true ~observations
                                ~capabilities ~reference
                                ~observation_identity:
                                  (Observation.identity target_observation)
                                ?region_fingerprint:(Region.fingerprint region)
                                ?display:(Region.summary region) ~observed_at
                                ())))))

let resolve_with_builtin ~workspace ~local ~observed_at ~observations
    ~capabilities ~regions ~reference =
  match Reference_resolver.resolve ~workspace ~regions reference with
  | Reference_resolver.Not_found ->
      diagnostic_result ~capabilities observations reference
        Diagnostic.Unresolved_ref
        ("reference " ^ local ^ " target does not resolve")
  | Reference_resolver.Read_failure ->
      diagnostic_result ~capabilities observations reference
        Diagnostic.Unresolved_ref
        ("reference " ^ local ^ " target cannot be read safely")
  | Reference_resolver.Invalid_selector message ->
      diagnostic_result ~capabilities observations reference
        Diagnostic.Invalid_selector message
  | Reference_resolver.Resolved resolved ->
      snapshot_result ~observations ~capabilities ~reference
        ~observation_identity:resolved.observation_identity
        ?region_fingerprint:resolved.region_fingerprint
        ?display:resolved.display ~observed_at ()

let resolve_inspected ~workspace ~reference:local ~observed_at ~registry
    inspected =
  match inspected_failure inspected with
  | Some result -> result
  | None ->
      let observations = Command_result.observations inspected in
      let capabilities = Command_result.capabilities inspected in
      match find_reference inspected local with
      | None -> usage "reference is not declared by the selected observation"
      | Some reference -> (
          match
            Reference.target reference |> Region_address.interpreter_identity
          with
          | None ->
              resolve_with_builtin ~workspace ~local ~observed_at ~observations
                ~capabilities ~regions:(Command_result.regions inspected)
                ~reference
          | Some interpreter -> (
              match Interpreter_dispatcher.find_exact registry interpreter with
              | Error message -> usage message
              | Ok (Some (Interpreter_dispatcher.Installed extension)) ->
                  resolve_with_installed_interpreter ~workspace ~local
                    ~observed_at ~observations ~capabilities ~reference ~extension
              | Ok (Some
                  (Interpreter_dispatcher.Built_in_markdown
                  | Interpreter_dispatcher.Built_in_jsonl
                  | Interpreter_dispatcher.Built_in_sidecar_v1)) ->
                  resolve_with_builtin ~workspace ~local ~observed_at
                    ~observations ~capabilities
                    ~regions:(Command_result.regions inspected) ~reference
              | Ok None ->
                  diagnostic_result ~capabilities observations reference
                    Diagnostic.Invalid_selector
                    (Printf.sprintf "required interpreter %s@%s is not installed"
                       (Interpreter.name interpreter)
                       (Interpreter.version interpreter))))

let resolve_reference_with_registry ~workspace ~observation ~reference
    ~observed_at ~registry =
  Workspace_inspect.inspect_with_registry ~workspace ~observation ~registry
  |> resolve_inspected ~workspace ~reference ~observed_at ~registry

let resolve_reference_with_extension ~workspace ~observation ~reference
    ~observed_at ~manifest ~executable ~arguments =
  let capability = Extension_manifest.capability manifest in
  if Capability.kind capability <> Capability.Interpreter then
    usage "extension resolve requires an interpreter capability"
  else
    match
      Installed_extension.make ~manifest ~executable ~arguments
      |> fun result ->
      Result.bind result (fun extension ->
          Registry_snapshot.make [ extension ]
          |> Result.map (fun registry -> (extension, registry)))
    with
    | Error message -> usage message
    | Ok (extension, registry) -> (
        match extension_associated_observation_type manifest observation with
        | Error message -> usage message
        | Ok _ -> (
            match
              Extension_runtime.with_checked_session ~executable ~arguments
                ~limits:Extension_runtime.default_limits ~manifest (fun session ->
                  Ok
                    (Workspace_inspect.inspect_with_extension_session ~workspace
                       ~observation ~manifest ~session))
            with
            | Error failure -> (
                match
                  runtime_extension_failure Extension_failure.Session failure
                with
                | Error _ -> internal "construct-extension-session-failure"
                | Ok failure -> extension_session_failure_result manifest failure)
            | Ok inspected ->
                ignore extension;
                resolve_inspected ~workspace ~reference ~observed_at ~registry
                  inspected))
