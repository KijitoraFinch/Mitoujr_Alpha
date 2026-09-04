let ( let* ) = Result.bind

let command_result ?summary ?(diagnostics = []) ?(observations = [])
    ?(sidecar_snapshots = []) ?(regions = []) ?(references = [])
    ?(annotations = []) ?(reference_definitions = []) ?(reference_uses = [])
    ?(annotation_occurrences = []) ?(capabilities = [])
    ?(coverage = Coverage.empty) ~termination () =
  match
    Command_result.make ~command:"check" ~termination
      ~effect:Command_result.No_change ~diagnostics ~observations
      ~sidecar_snapshots ~regions ~references ~annotations
      ~reference_definitions ~reference_uses ~annotation_occurrences
      ~capabilities ~coverage ?summary ()
  with
  | Ok result -> result
  | Error _ ->
      Command_result.internal_error ~command:"check"
        ~error_code:"internal-invariant" ~operation:"construct-command-result"

let unique compare values =
  let sorted = List.sort compare values in
  let rec loop previous reversed = function
    | [] -> List.rev reversed
    | value :: rest ->
        if Option.fold ~none:false ~some:(fun item -> compare item value = 0) previous
        then loop previous reversed rest
        else loop (Some value) (value :: reversed) rest
  in
  loop None [] sorted

let diagnostic ?location ~code ~message () =
  Diagnostic.make ~code ~message ?location ()

let snapshot_has_diagnostic snapshot code message =
  Workspace_graph_snapshot.diagnostics snapshot
  |> List.exists (fun diagnostic ->
         Diagnostic.code diagnostic = code
         && String.equal (Diagnostic.message diagnostic) message)

let location_of_source = function
  | Source_location.In_observation source ->
      Some
        {
          Diagnostic.observation = Some source.observation;
          region = None;
          annotation = None;
          range =
            (match source.locator with
            | Source_location.Byte_range range -> Some range
            | Source_location.Structured _ -> None);
        }
  | Source_location.In_sidecar _ -> None

let target_fingerprint snapshot observation address =
  match Region_address.selector address with
  | Selector.Whole_observation -> None
  | Selector.Text_range range ->
      Observation.bytes observation
      |> Option.map (fun content ->
             String.sub content (Text_range.start range)
               (Text_range.length range)
             |> Fingerprint.sha256)
  | Selector.Row_filter filter ->
      Option.bind (Observation.bytes observation) (fun content ->
          match Jsonl_interpreter.select filter content with
          | Ok (Jsonl_interpreter.One selected) ->
              Some (Fingerprint.sha256 selected.display)
          | Ok Jsonl_interpreter.No_match
          | Ok Jsonl_interpreter.Ambiguous
          | Error _ ->
              None)
  | Selector.Region_id _ | Selector.Extension _ ->
      Workspace_graph_snapshot.regions snapshot
      |> List.find_opt (fun region ->
             Observation_id.equal (Observation.id observation)
               (Region.observation region)
             && Selector.compare (Region.selector region)
                  (Region_address.selector address)
                = 0
             &&
             match Region_address.interpreter_identity address with
             | None -> true
             | Some expected ->
                 Region.interpreter_identity region
                 |> Option.fold ~none:false ~some:(Interpreter.equal expected))
      |> fun region -> Option.bind region Region.fingerprint

let address_expectation_matches snapshot address =
  match Region_address.expectation address with
  | None -> true
  | Some expectation -> (
      match Workspace_graph.target_observation snapshot address with
      | None -> false
      | Some observation ->
          Expectation.matches ~origin:(Observation.origin observation)
            ~observation_identity:(Observation.identity observation)
            ~content_identity:(Observation.content_identity observation)
            ~fingerprint:(target_fingerprint snapshot observation address)
            expectation)

let region_ref_resolution snapshot = function
  | Region_ref.Resolved id ->
      if
        Workspace_graph_snapshot.regions snapshot
        |> List.exists (fun region -> Region_id.equal id (Region.id region))
      then Endpoint_resolution.Resolved
      else Endpoint_resolution.Unresolved
  | Region_ref.Address address -> Workspace_graph.resolve_address snapshot address

let region_ref_expectation_matches snapshot = function
  | Region_ref.Resolved _ -> true
  | Region_ref.Address address -> address_expectation_matches snapshot address

let annotation_region_diagnostics ~role ~snapshot ~location region diagnostics =
  match region_ref_resolution snapshot region with
  | Endpoint_resolution.Invalid_selector ->
      let* item =
        diagnostic ?location ~code:Diagnostic.Invalid_selector
          ~message:
            ("annotation " ^ role
           ^ " is not supported by its interpreter")
          ()
      in
      Ok (item :: diagnostics)
  | Endpoint_resolution.Unresolved
  | Endpoint_resolution.Unreadable
  | Endpoint_resolution.Not_checked ->
      let* item =
        diagnostic ?location ~code:Diagnostic.Stale_selector
          ~message:("annotation " ^ role ^ " selector does not resolve") ()
      in
      Ok (item :: diagnostics)
  | Endpoint_resolution.Resolved ->
      if region_ref_expectation_matches snapshot region then Ok diagnostics
      else
        let* item =
          diagnostic ?location ~code:Diagnostic.Expectation_failed
            ~message:
              ("annotation " ^ role ^ " does not satisfy its expectation")
            ()
        in
        Ok (item :: diagnostics)

let annotation_reference_diagnostics ~snapshot ~location annotation diagnostics =
  match Annotation.object_ annotation with
  | Annotation.Reference_object id -> (
      match
        Workspace_graph_snapshot.reference_index snapshot
        |> Reference_index.find id
      with
      | None ->
          let local =
            Annotation.id annotation |> Annotation_id.local
            |> Identifier.to_string
          in
          let message =
            "annotation " ^ local ^ " refers to an undefined reference"
          in
          if snapshot_has_diagnostic snapshot Diagnostic.Unresolved_ref message
          then Ok diagnostics
          else
            let* item =
              diagnostic ?location ~code:Diagnostic.Unresolved_ref ~message ()
            in
            Ok (item :: diagnostics)
      | Some (Reference_index.Consistent _ | Reference_index.Conflict _) ->
          Ok diagnostics)
  | Annotation.Region_object _ | Annotation.Literal _ -> Ok diagnostics

let annotation_diagnostics snapshot index =
  Annotation_index.entries index
  |> List.fold_left
       (fun result (_id, entry) ->
         let* diagnostics = result in
         match entry with
         | Annotation_index.Conflict { occurrences } ->
             let occurrence = Nonempty.head occurrences in
             let annotation = Annotation_occurrence.annotation occurrence in
             let local =
               Annotation.id annotation |> Annotation_id.local
               |> Identifier.to_string
             in
             let message =
               "annotation " ^ local ^ " has divergent occurrences"
             in
             if snapshot_has_diagnostic snapshot Diagnostic.Divergent message
             then Ok diagnostics
             else
               let* item =
                 diagnostic ?location:(location_of_source
                   (Annotation_occurrence.source occurrence))
                   ~code:Diagnostic.Divergent ~message ()
               in
               Ok (item :: diagnostics)
         | Annotation_index.Consistent { value = annotation; occurrences } ->
             let first = Nonempty.head occurrences in
             let location =
               location_of_source (Annotation_occurrence.source first)
             in
             let* diagnostics =
               annotation_region_diagnostics ~role:"subject" ~snapshot
                 ~location (Annotation.subject annotation) diagnostics
             in
             let* diagnostics =
               match Annotation.object_ annotation with
               | Annotation.Region_object region ->
                   annotation_region_diagnostics ~role:"object" ~snapshot
                     ~location region diagnostics
               | Annotation.Reference_object _ | Annotation.Literal _ ->
                   Ok diagnostics
             in
             let* diagnostics =
               annotation_reference_diagnostics ~snapshot ~location annotation
                 diagnostics
             in
             let has_observation =
               Nonempty.exists
                 (fun occurrence ->
                   match Annotation_occurrence.source occurrence with
                   | Source_location.In_observation _ -> true
                   | Source_location.In_sidecar _ -> false)
                 occurrences
             in
             let has_sidecar =
               Nonempty.exists
                 (fun occurrence ->
                   match Annotation_occurrence.source occurrence with
                   | Source_location.In_sidecar _ -> true
                   | Source_location.In_observation _ -> false)
                 occurrences
             in
             if has_observation && has_sidecar then Ok diagnostics
             else
               let code, message =
                 if has_sidecar then
                   ( Diagnostic.Sidecar_only,
                     "annotation is recorded only in Sidecar metadata" )
                 else
                   ( Diagnostic.Inline_only,
                     "annotation is recorded only in the primary Observation" )
               in
               let* item = diagnostic ?location ~code ~message () in
               Ok (item :: diagnostics))
       (Ok [])
  |> Result.map List.rev

let named_uses reference_uses annotations =
  let from_uses =
    List.filter_map
      (fun use ->
        match Reference_use.target use with
        | Reference_use.Named id -> Some id
        | Reference_use.Direct _ -> None)
      reference_uses
  in
  let from_annotations =
    List.filter_map
      (fun annotation ->
        match Annotation.object_ annotation with
        | Annotation.Reference_object id -> Some id
        | Annotation.Region_object _ | Annotation.Literal _ -> None)
      annotations
  in
  from_uses @ from_annotations

let reference_use_diagnostics ~snapshot reference_uses =
  let index = Workspace_graph_snapshot.reference_index snapshot in
  reference_uses
  |> List.fold_left
       (fun result use ->
         let* diagnostics = result in
         match Reference_use.target use with
         | Reference_use.Direct _ -> Ok diagnostics
         | Reference_use.Named id -> (
             match Reference_index.find id index with
             | Some (Reference_index.Consistent _) -> Ok diagnostics
             | Some (Reference_index.Conflict _) | None ->
                 let local = Reference_id.local id |> Identifier.to_string in
                 let message =
                   "reference use " ^ local
                   ^ " does not have a consistent definition"
                 in
                 let location =
                   Some
                     {
                       Diagnostic.observation =
                         Some (Reference_use.source_observation use);
                       region = None;
                       annotation = None;
                       range = Some (Reference_use.source_range use);
                     }
                 in
                 let* item =
                   diagnostic ?location ~code:Diagnostic.Unresolved_ref
                     ~message ()
                 in
                 Ok (item :: diagnostics)))
       (Ok [])
  |> Result.map List.rev

let reference_diagnostics ~snapshot ~used index =
  Reference_index.entries index
  |> List.fold_left
       (fun result (_id, entry) ->
         let* diagnostics = result in
         match entry with
         | Reference_index.Conflict { occurrences } ->
             let occurrence = Nonempty.head occurrences in
             let reference =
               Reference_definition_occurrence.reference occurrence
             in
             let local =
               Reference.id reference |> Reference_id.local
               |> Identifier.to_string
             in
             let message =
               "reference " ^ local ^ " has divergent definitions"
             in
             if snapshot_has_diagnostic snapshot Diagnostic.Divergent message
             then Ok diagnostics
             else
               let* item =
                 diagnostic
                   ?location:(location_of_source
                     (Reference_definition_occurrence.source occurrence))
                   ~code:Diagnostic.Divergent ~message ()
               in
               Ok (item :: diagnostics)
         | Reference_index.Consistent { value = reference; occurrences } ->
             let location =
               Nonempty.head occurrences |> Reference_definition_occurrence.source
               |> location_of_source
             in
             let id = Reference.id reference in
             let local = Reference_id.local id |> Identifier.to_string in
             let* diagnostics =
               if List.exists (Reference_id.equal id) used then Ok diagnostics
               else
                 let* item =
                   diagnostic ?location ~code:Diagnostic.Unreferenced_ref
                     ~message:("reference " ^ local ^ " is declared but not used")
                     ()
                 in
                 Ok (item :: diagnostics)
             in
             let target = Reference.target reference in
             (match Workspace_graph.resolve_address snapshot target with
             | Endpoint_resolution.Unresolved ->
                 let* item =
                   diagnostic ?location ~code:Diagnostic.Unresolved_ref
                     ~message:("reference " ^ local ^ " target does not resolve")
                     ()
                 in
                 Ok (item :: diagnostics)
             | Endpoint_resolution.Unreadable ->
                 let* item =
                   diagnostic ?location ~code:Diagnostic.Unresolved_ref
                     ~message:
                       ("reference " ^ local
                      ^ " target cannot be read safely")
                     ()
                 in
                 Ok (item :: diagnostics)
             | Endpoint_resolution.Invalid_selector ->
                 let* item =
                   diagnostic ?location ~code:Diagnostic.Invalid_selector
                     ~message:
                       ("reference " ^ local
                      ^ " target selector is invalid for the fixed Observation")
                     ()
                 in
                 Ok (item :: diagnostics)
             | Endpoint_resolution.Not_checked ->
                 let* item =
                   diagnostic ?location ~code:Diagnostic.Unresolved_ref
                     ~message:
                       ("reference " ^ local
                      ^ " target has no available Resource Observer")
                     ()
                 in
                 Ok (item :: diagnostics)
             | Endpoint_resolution.Resolved ->
                 let expectations_match =
                   match Reference.resolution_expectations reference with
                   | [] -> true
                   | expectations -> (
                       match
                         Workspace_graph.target_observation snapshot target
                       with
                       | Some observation ->
                           let fingerprint =
                             target_fingerprint snapshot observation target
                           in
                           List.for_all
                             (Expectation.matches
                                ~origin:(Observation.origin observation)
                                ~observation_identity:
                                  (Observation.identity observation)
                                ~content_identity:
                                  (Observation.content_identity observation)
                                ~fingerprint)
                             expectations
                       | None -> false)
                 in
                 if expectations_match then Ok diagnostics
                 else
                   let* item =
                     diagnostic ?location ~code:Diagnostic.Expectation_failed
                       ~message:
                         ("reference " ^ local
                        ^ " target does not satisfy its expectation")
                       ()
                   in
                   Ok (item :: diagnostics)))
       (Ok [])
  |> Result.map List.rev

let annotation_occurrences index =
  Annotation_index.entries index
  |> List.concat_map (fun (_, entry) ->
         match entry with
         | Annotation_index.Consistent { occurrences; _ }
         | Annotation_index.Conflict { occurrences } ->
             Nonempty.to_list occurrences)
  |> List.sort Annotation_occurrence.compare

let reference_definitions index =
  Reference_index.entries index
  |> List.concat_map (fun (_, entry) ->
         match entry with
         | Reference_index.Consistent { occurrences; _ }
         | Reference_index.Conflict { occurrences } ->
             Nonempty.to_list occurrences)
  |> List.sort Reference_definition_occurrence.compare

let extension_failure_diagnostic failure =
  Diagnostic.make ~code:Diagnostic.Extension_failure
    ~message:(Extension_failure.message failure) ~extension_failure:failure ()

let runtime_failure operation failure =
  Extension_failure.make ~operation
    ~code:(Extension_runtime.failure_code failure)
    ~message:(Extension_runtime.failure_message failure)
    ?data:(Extension_runtime.failure_data failure) ()

let invalid_audit_result message =
  Extension_failure.make ~operation:Extension_failure.Audit
    ~code:"invalid-extension-result" ~message
    ~data:(`Assoc [ ("decoder", `String "monika.audit") ]) ()

let run_extension_auditor ~snapshot ~policy extension =
  let manifest = Installed_extension.manifest extension in
  match
    Extension_runtime.with_checked_session
      ~executable:(Installed_extension.executable extension)
      ~arguments:(Installed_extension.arguments extension)
      ~authority:(Installed_extension.authority extension)
      ~limits:Extension_runtime.default_limits ~manifest (fun session ->
        Extension_runtime.call session ~method_name:"monika.audit"
          ~params:(Extension_protocol.audit_params ~snapshot ~policy))
  with
  | Error failure ->
      let* failure = runtime_failure Extension_failure.Audit failure in
      let* diagnostic = extension_failure_diagnostic failure in
      Ok [ diagnostic ]
  | Ok result -> (
      match Extension_protocol.decode_audit_result ~policy result with
      | Ok (Extension_protocol.Audit_diagnostics diagnostics) -> Ok diagnostics
      | Ok (Extension_protocol.Audit_failure failure) ->
          let* diagnostic = extension_failure_diagnostic failure in
          Ok [ diagnostic ]
      | Error message ->
          let* failure = invalid_audit_result message in
          let* diagnostic = extension_failure_diagnostic failure in
          Ok [ diagnostic ])

let extension_audits ~snapshot ~policy registry =
  Auditor_dispatcher.select_all registry
  |> List.fold_left
       (fun result selected ->
         let* diagnostics, capabilities = result in
         match selected with
         | Auditor_dispatcher.Built_in_workspace_check ->
             Ok (diagnostics, capabilities)
         | Auditor_dispatcher.Installed extension ->
             let* emitted = run_extension_auditor ~snapshot ~policy extension in
             Ok
               ( List.rev_append emitted diagnostics,
                 Installed_extension.capability extension :: capabilities ))
       (Ok ([], []))
  |> Result.map (fun (diagnostics, capabilities) ->
         (List.rev diagnostics, List.rev capabilities))

let check_with_registry ~workspace ~registry ~policy =
  match Workspace_graph.build_snapshot_with_registry ~workspace ~registry with
  | Error (Workspace_graph.Usage message) ->
      command_result
        ~termination:(Command_result.Usage_failure message)
        ~summary:[ ("message", Command_result.Text message) ] ()
  | Error (Workspace_graph.Internal _) ->
      command_result
        ~termination:
          (Command_result.Internal_failure "internal operation failed")
        ~summary:
          [
            ("errorCode", Command_result.Text "workspace-graph-failure");
            ("operation", Command_result.Text "build-workspace-graph");
          ]
        ()
  | Ok snapshot ->
      let observations = Workspace_graph_snapshot.observations snapshot in
      let sidecar_snapshots =
        Workspace_graph_snapshot.sidecar_snapshots snapshot
      in
      let regions = Workspace_graph_snapshot.regions snapshot in
      let reference_index =
        Workspace_graph_snapshot.reference_index snapshot
      in
      let annotation_index =
        Workspace_graph_snapshot.annotation_index snapshot
      in
      let reference_uses =
        Workspace_graph_snapshot.reference_uses snapshot
      in
      let reference_definitions = reference_definitions reference_index in
      let annotation_occurrences = annotation_occurrences annotation_index in
      let references = Reference_index.consistent_values reference_index in
      let annotations = Annotation_index.consistent_values annotation_index in
      let used = named_uses reference_uses annotations in
      (match
         ( annotation_diagnostics snapshot annotation_index,
           reference_diagnostics ~snapshot ~used reference_index,
           reference_use_diagnostics ~snapshot reference_uses,
           extension_audits ~snapshot ~policy registry )
       with
      | Error _, _, _, _ | _, Error _, _, _ | _, _, Error _, _
      | _, _, _, Error _ ->
          Command_result.internal_error ~command:"check"
            ~error_code:"internal-invariant"
            ~operation:"construct-diagnostic"
      | Ok annotation_diagnostics, Ok reference_diagnostics,
        Ok reference_use_diagnostics,
        Ok (extension_diagnostics, capabilities) ->
          let diagnostics =
            Workspace_graph_snapshot.diagnostics snapshot
            |> List.filter (fun diagnostic ->
                   Diagnostic.code diagnostic
                   <> Diagnostic.Unsupported_observation)
            |> fun graph_diagnostics ->
            graph_diagnostics @ annotation_diagnostics @ reference_diagnostics
            @ reference_use_diagnostics @ extension_diagnostics
            |> Audit_policy.apply policy
            |> unique Diagnostic.compare
          in
          command_result ~termination:Command_result.Completed ~diagnostics
            ~observations ~sidecar_snapshots ~regions ~references ~annotations
            ~reference_definitions ~reference_uses ~annotation_occurrences
            ~capabilities
            ~coverage:(Workspace_graph_snapshot.coverage snapshot)
            ~summary:
              [
                ("diagnostics", Command_result.Count (List.length diagnostics));
              ]
            ())

let check ~workspace =
  check_with_registry ~workspace ~registry:Registry_snapshot.empty
    ~policy:Audit_policy.default
