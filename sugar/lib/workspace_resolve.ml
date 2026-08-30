let command_result ?summary ?(diagnostics = []) ?(snapshots = [])
    ?(observations = []) ?(regions = []) ?(capabilities = []) ~termination () =
  match
    Command_result.make ~command:"resolve" ~termination
      ~effect:Command_result.No_change ~diagnostics ~snapshots ~observations
      ~regions ~capabilities ?summary ()
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

let diagnostic_result ?(capabilities = []) ?(diagnostics = [])
    ?extension_failure observations code message =
  match
    Diagnostic.make ~code ~message ?extension_failure ()
  with
  | Error _ -> internal "construct-diagnostic"
  | Ok diagnostic ->
      command_result ~termination:Command_result.Completed ~observations
        ~capabilities ~diagnostics:(diagnostic :: diagnostics)
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

let validate_previous_snapshot reference = function
  | None -> Ok ()
  | Some previous -> (
      match Reference.binding reference with
      | Reference.Pinned | Reference.Floating ->
          Error
            "--previous-snapshot is valid only for a tracking reference"
      | Reference.Tracking ->
          if
            Reference.compare_target (Reference.target reference)
              (Resolution_snapshot.target previous)
            = 0
          then Ok ()
          else
            Error
              "--previous-snapshot target does not match the selected reference")

let snapshot_result ?(runtime_checked = false) ~observations ~capabilities
    ~diagnostics:source_diagnostics ~label ~target ~expectations ~tracking
    ?previous_snapshot
    ~observation_identity ~content_identity ~region ?region_fingerprint ?display
    ~observed_at () =
  let expectations_match =
    expectations
    |> List.for_all
         (Expectation.matches
            ~origin:(Region_address.origin target)
            ~observation_identity ~content_identity
            ~fingerprint:region_fingerprint)
  in
  if not expectations_match then
    diagnostic_result ~capabilities ~diagnostics:source_diagnostics observations
      Diagnostic.Expectation_failed
      (label ^ " does not satisfy its expectation")
  else
    match
      Resolution_snapshot.make ~target
        ~observation_identity ?region_fingerprint ?display ~observed_at ()
    with
    | Error _ -> internal "construct-resolution-snapshot"
    | Ok snapshot ->
      let resolution_diagnostics =
        match previous_snapshot, tracking with
        | Some previous, true
          when not (Resolution_snapshot.same_resolution previous snapshot) ->
            Diagnostic.make ~code:Diagnostic.Resolution_changed
              ~message:(label ^ " resolves differently from the previous snapshot")
              ()
            |> Result.map (fun diagnostic -> [ diagnostic ])
        | None, _ | Some _, false | Some _, true ->
            Ok []
      in
      (match resolution_diagnostics with
      | Error _ -> internal "construct-resolution-changed-diagnostic"
      | Ok resolution_diagnostics ->
          let summary =
            [ ("snapshots", Command_result.Count 1) ]
            @
            if runtime_checked then
              [ ("runtimeChecked", Command_result.Flag true) ]
            else []
          in
          let diagnostics =
            List.rev_append resolution_diagnostics source_diagnostics
          in
          command_result ~termination:Command_result.Completed ~observations
            ~regions:[ region ] ~capabilities ~diagnostics
            ~snapshots:[ snapshot ] ~summary ())

let inspected_termination_failure inspected =
  match Command_result.termination inspected with
  | Command_result.Usage_failure message -> Some (usage message)
  | Command_result.Internal_failure _ -> Some (internal "inspect-observation")
  | Command_result.Completed -> None

let target_observation ~observation_type path file =
  let ( let* ) = Result.bind in
  let* id =
    Observation_id.make
      ("observation:" ^ Workspace_path.to_canonical_string path)
  in
  Ok
    (Observation.of_bytes ~id ~origin:(Observation.workspace path)
       ~observation_type ~bytes:(Workspace_read.content file))

let add_capability capabilities capability =
  if
    List.exists
      (fun candidate -> Capability.compare candidate capability = 0)
      capabilities
  then capabilities
  else capability :: capabilities

let add_observation observations observation =
  if
    List.exists
      (fun candidate ->
        Observation_id.equal (Observation.id candidate)
          (Observation.id observation))
      observations
  then observations
  else observation :: observations

let resolution_result ~registry ~label ~target ~expectations ~tracking
    ~observed_at ~observations ~capabilities ~diagnostics ~previous_snapshot
    ~target_observation ~existing_regions =
  let selected =
    match Region_address.interpreter_identity target with
    | None -> Ok None
    | Some interpreter -> Interpreter_dispatcher.find_exact registry interpreter
  in
  match selected with
  | Error message -> usage message
  | Ok selected ->
      let capabilities, runtime_checked =
        match selected with
        | Some (Interpreter_dispatcher.Installed extension) ->
            ( add_capability capabilities
                (Installed_extension.capability extension),
              true )
        | None
        | Some
            (Interpreter_dispatcher.Built_in_markdown
            | Interpreter_dispatcher.Built_in_jsonl) ->
            (capabilities, false)
      in
      (match
         Region_address_resolver.resolve ~registry
           ~observation:target_observation ~existing_regions target
       with
      | Error message -> usage message
      | Ok outcome -> (
          match Region_address_resolver.resolution outcome with
          | Endpoint_resolution.Resolved -> (
              match Region_address_resolver.region outcome with
              | None -> internal "resolve-region-without-region"
              | Some region ->
                  snapshot_result ~runtime_checked ~observations ~capabilities
                    ~diagnostics ~label ~target ~expectations ~tracking
                    ?previous_snapshot
                    ~observation_identity:
                      (Observation.identity target_observation)
                    ~content_identity:
                      (Observation.content_identity target_observation)
                    ~region ?region_fingerprint:(Region.fingerprint region)
                    ?display:(Region.summary region) ~observed_at ())
          | Endpoint_resolution.Invalid_selector ->
              let message =
                Region_address_resolver.message outcome
                |> Option.value ~default:"target selector is invalid"
              in
              diagnostic_result ~capabilities ~diagnostics
                ?extension_failure:
                  (Region_address_resolver.extension_failure outcome)
                observations Diagnostic.Invalid_selector message
          | Endpoint_resolution.Unresolved
          | Endpoint_resolution.Unreadable
          | Endpoint_resolution.Not_checked ->
              let message =
                Region_address_resolver.message outcome
                |> Option.value ~default:(label ^ " does not resolve")
              in
              diagnostic_result ~capabilities ~diagnostics
                ?extension_failure:
                  (Region_address_resolver.extension_failure outcome)
                observations Diagnostic.Unresolved_ref message))

let resolve_extension_origin ~previous_snapshot ~label ~target ~expectations
    ~tracking ~observed_at ~registry ~observations ~capabilities ~diagnostics =
  let origin = Region_address.origin target in
  match Resource_observer_runner.observe registry origin with
  | Error message -> usage message
  | Ok Resource_observer_runner.Unsupported ->
      diagnostic_result ~capabilities ~diagnostics observations
        Diagnostic.Unresolved_ref
        (label ^ " has no available Resource Observer")
  | Ok (Resource_observer_runner.Failure { capability; failure }) ->
      let capabilities =
        Option.fold ~none:capabilities
          ~some:(add_capability capabilities) capability
      in
      diagnostic_result ~capabilities ~diagnostics ~extension_failure:failure
        observations Diagnostic.Unresolved_ref (Extension_failure.message failure)
  | Ok (Resource_observer_runner.Observed { capability; observation }) ->
      let capabilities = add_capability capabilities capability in
      let observations = add_observation observations observation in
      resolution_result ~registry ~label ~target ~expectations ~tracking
        ~observed_at ~observations ~capabilities ~diagnostics ~previous_snapshot
        ~target_observation:observation ~existing_regions:[]

let resolve_workspace_origin ~previous_snapshot ~workspace ~label ~target
    ~expectations ~tracking ~observed_at ~registry ~observations ~capabilities
    ~diagnostics ~regions path =
  let origin = Observation.workspace path in
  match
    List.find_opt
      (fun observation -> Origin.equal origin (Observation.origin observation))
      observations
  with
  | Some target_observation ->
      let existing_regions =
        List.filter
          (fun region ->
            Observation_id.equal (Observation.id target_observation)
              (Region.observation region))
          regions
      in
      resolution_result ~registry ~label ~target ~expectations ~tracking
        ~observed_at ~observations ~capabilities ~diagnostics ~previous_snapshot
        ~target_observation ~existing_regions
  | None -> (
      match Workspace_read.read ~workspace ~path with
      | Error Workspace_read.Missing_file ->
          diagnostic_result ~capabilities ~diagnostics observations
            Diagnostic.Unresolved_ref (label ^ " does not resolve")
      | Error _ ->
          diagnostic_result ~capabilities ~diagnostics observations
            Diagnostic.Unresolved_ref (label ^ " cannot be read safely")
      | Ok file -> (
          match Interpreter_dispatcher.classify_path registry path with
          | Error message -> usage message
          | Ok observation_type -> (
              match target_observation ~observation_type path file with
              | Error _ -> internal "construct-target-observation"
              | Ok target_observation ->
                  let observations =
                    add_observation observations target_observation
                  in
                  resolution_result ~registry ~label ~target ~expectations
                    ~tracking ~observed_at ~observations ~capabilities
                    ~diagnostics ~previous_snapshot ~target_observation
                    ~existing_regions:[])))

let resolve_inspected ?previous_snapshot ~workspace ~reference:local
    ~observed_at ~registry inspected =
  match inspected_termination_failure inspected with
  | Some result -> result
  | None ->
      let observations = Command_result.observations inspected in
      let capabilities = Command_result.capabilities inspected in
      let diagnostics = Command_result.diagnostics inspected in
      match find_reference inspected local with
      | None when diagnostics = [] ->
          usage "reference is not declared by the selected observation"
      | None ->
          command_result ~termination:Command_result.Completed ~observations
            ~capabilities ~diagnostics
            ~summary:[ ("snapshots", Command_result.Count 0) ] ()
      | Some reference -> (
          match validate_previous_snapshot reference previous_snapshot with
          | Error message -> usage message
          | Ok () ->
              let target = Reference.target reference in
              let label = "reference " ^ local ^ " target" in
              let expectations = Reference.resolution_expectations reference in
              let tracking = Reference.binding reference = Reference.Tracking in
              match Region_address.origin target with
              | Origin.Extension _ ->
                  resolve_extension_origin ~label ~target ~expectations
                    ~tracking ~observed_at ~registry ~observations ~capabilities
                    ~diagnostics ~previous_snapshot
              | Origin.Workspace path ->
                  resolve_workspace_origin ~workspace ~label ~target
                    ~expectations ~tracking ~observed_at ~registry ~observations
                    ~capabilities ~regions:(Command_result.regions inspected)
                    ~diagnostics ~previous_snapshot path
              | Origin.Git _ | Origin.Web _ | Origin.Generated _
              | Origin.External _ ->
                  diagnostic_result ~capabilities ~diagnostics observations
                    Diagnostic.Unresolved_ref
                    (label ^ " has no available Resource Observer"))

let resolve_address_with_registry ~workspace ~address ~observed_at ~registry =
  let label = "RegionAddress target" in
  let expectations = Option.to_list (Region_address.expectation address) in
  match Region_address.origin address with
  | Origin.Extension _ ->
      resolve_extension_origin ~previous_snapshot:None ~label ~target:address
        ~expectations ~tracking:false ~observed_at ~registry ~observations:[]
        ~capabilities:[] ~diagnostics:[]
  | Origin.Workspace path ->
      resolve_workspace_origin ~previous_snapshot:None ~workspace ~label
        ~target:address ~expectations ~tracking:false ~observed_at ~registry
        ~observations:[] ~capabilities:[] ~diagnostics:[] ~regions:[] path
  | Origin.Git _ | Origin.Web _ | Origin.Generated _ | Origin.External _ ->
      diagnostic_result [] Diagnostic.Unresolved_ref
        (label ^ " has no available Resource Observer")

let resolve_address ~workspace ~address ~observed_at =
  resolve_address_with_registry ~workspace ~address ~observed_at
    ~registry:Registry_snapshot.empty

let resolve_reference_with_registry ~previous_snapshot ~workspace ~observation
    ~reference ~observed_at ~registry =
  Workspace_inspect.inspect_with_registry ~workspace ~observation ~registry
  |> resolve_inspected ~workspace ~reference ~observed_at ~registry
       ?previous_snapshot

let resolve_reference ~previous_snapshot ~workspace ~observation ~reference
    ~observed_at =
  resolve_reference_with_registry ~previous_snapshot ~workspace ~observation
    ~reference ~observed_at ~registry:Registry_snapshot.empty

let require_extension_association manifest path =
  let capability = Extension_manifest.capability manifest in
  match Extension_applicability.associate capability ~path with
  | Error _ as error -> error
  | Ok Extension_applicability.Not_associated ->
      Error "extension does not apply to the selected observation"
  | Ok (Extension_applicability.Associated _) -> Ok ()

let resolve_reference_with_extension ~previous_snapshot ~workspace ~observation
    ~reference ~observed_at ~manifest ~executable ~arguments ~authority =
  let capability = Extension_manifest.capability manifest in
  if Capability.kind capability <> Capability.Interpreter then
    usage "extension resolve requires an interpreter capability"
  else
    match
      Installed_extension.make ~manifest ~executable ~arguments
        ~authority
      |> fun result ->
      Result.bind result (fun extension ->
          Registry_snapshot.make [ extension ]
          |> Result.map (fun registry -> (extension, registry)))
    with
    | Error message -> usage message
    | Ok (extension, registry) -> (
        match require_extension_association manifest observation with
        | Error message -> usage message
        | Ok () -> (
            match
              Extension_runtime.with_checked_session ~executable ~arguments
                ~authority
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
                  ?previous_snapshot inspected))

let resolve_address_with_extension ~workspace ~address ~observed_at ~manifest
    ~executable ~arguments ~authority =
  let capability = Extension_manifest.capability manifest in
  if Capability.kind capability <> Capability.Interpreter then
    usage "direct address extension must be an interpreter capability"
  else
    match
      Installed_extension.make ~manifest ~executable ~arguments ~authority
      |> fun result ->
      Result.bind result (fun extension ->
          Registry_snapshot.make [ extension ])
    with
    | Error message -> usage message
    | Ok registry ->
        resolve_address_with_registry ~workspace ~address ~observed_at ~registry
