let ( let* ) = Result.bind

let command_result ?summary ?(diagnostics = []) ?(patches = [])
    ?(observations = []) ?(capabilities = []) ?(coverage = Coverage.empty)
    ~termination ~effect () =
  match
    Command_result.make ~command:"derive" ~termination ~effect ~diagnostics
      ~patches ~observations ~capabilities ~coverage ?summary ()
  with
  | Ok result -> result
  | Error _ ->
      Command_result.internal_error ~command:"derive"
        ~error_code:"internal-invariant" ~operation:"construct-command-result"

let usage message =
  command_result ~termination:(Command_result.Usage_failure message)
    ~effect:Command_result.No_change
    ~summary:[ ("message", Command_result.Text message) ] ()

let internal operation =
  command_result
    ~termination:(Command_result.Internal_failure "internal operation failed")
    ~effect:Command_result.No_change
    ~summary:
      [
        ("errorCode", Command_result.Text "filesystem-io");
        ("operation", Command_result.Text operation);
      ]
    ()

let has_inline occurrence =
  match Annotation_occurrence.source occurrence with
  | Source_location.In_observation _ -> true
  | Source_location.In_sidecar _ -> false

let required_reference_ids annotations =
  List.filter_map
    (fun annotation ->
      match Annotation.object_ annotation with
      | Annotation.Reference_object id -> Some id
      | Annotation.Region_object _ | Annotation.Literal _ -> None)
    annotations

let select_references references ids =
  List.filter
    (fun reference ->
      List.exists
        (fun id -> Reference_id.equal id (Reference.id reference))
        ids)
    references

let all_annotation_occurrences index =
  Annotation_index.entries index
  |> List.concat_map (fun (_, entry) ->
         match entry with
         | Annotation_index.Consistent { occurrences; _ }
         | Annotation_index.Conflict { occurrences } ->
             Nonempty.to_list occurrences)

let all_reference_definitions index =
  Reference_index.entries index
  |> List.concat_map (fun (_, entry) ->
         match entry with
         | Reference_index.Consistent { occurrences; _ }
         | Reference_index.Conflict { occurrences } ->
             Nonempty.to_list occurrences)

let source_observation_is observation = function
  | Source_location.In_observation source ->
      Observation_id.equal source.observation observation
  | Source_location.In_sidecar _ -> false

let snapshot_values snapshot primary =
  let primary_id = Observation.id primary in
  let annotation_occurrences =
    Workspace_graph_snapshot.annotation_index snapshot
    |> all_annotation_occurrences
    |> List.filter (fun occurrence ->
           has_inline occurrence
           && source_observation_is primary_id
                (Annotation_occurrence.source occurrence))
  in
  let reference_definitions =
    Workspace_graph_snapshot.reference_index snapshot
    |> all_reference_definitions
    |> List.filter (fun occurrence ->
           source_observation_is primary_id
             (Reference_definition_occurrence.source occurrence))
  in
  let annotation_index = Annotation_index.make annotation_occurrences in
  let reference_index = Reference_index.make reference_definitions in
  ( Annotation_index.consistent_values annotation_index,
    Reference_index.consistent_values reference_index )

let invalid_sidecar ~coverage observations observation_id message =
  match
    Diagnostic.make ~code:Diagnostic.Invalid_sidecar ~message
      ~location:
        {
          Diagnostic.observation = Some observation_id;
          region = None;
          annotation = None;
          range = None;
      }
      ()
  with
  | Error _ -> internal "construct-invalid-sidecar-diagnostic"
  | Ok diagnostic ->
      command_result ~termination:Command_result.Completed
        ~effect:Command_result.No_change ~observations ~diagnostics:[ diagnostic ]
        ~coverage
        ~summary:[ ("patches", Command_result.Count 0) ] ()

let patch ~primary_path ~sidecar_snapshot ~references ~annotations =
  let sidecar_path = Sidecar_snapshot.path sidecar_snapshot in
  let content = Sidecar_snapshot.bytes sidecar_snapshot in
  let* replacement =
    Sidecar_render.derived_section ~primary_path ~references ~annotations
  in
  let* existing = Sidecar_edit.optional_derived_section_range content in
  let* range, replacement =
    match existing with
    | Some range -> Ok (range, replacement)
    | None ->
        let* offset = Sidecar_edit.derived_insertion_offset content in
        let prefix =
          if offset = 0 || content.[offset - 1] = '\n' then "" else "\n"
        in
        let* range = Text_range.make ~start:offset ~end_:offset in
        Ok (range, prefix ^ replacement)
  in
  let* edit = Text_edit.make ~range ~replacement in
  let start = Text_range.start range in
  let end_ = Text_range.end_ range in
  let resulting_content =
    String.sub content 0 start ^ replacement
    ^ String.sub content end_ (String.length content - end_)
  in
  let patch_identity =
    String.concat "\000"
      [
        "inline-to-sidecar";
        "2";
        "edit";
        Workspace_path.to_canonical_string sidecar_path;
        (let identity = Sidecar_snapshot.content_identity sidecar_snapshot in
         Content_identity.display_hash identity ^ ":"
         ^ string_of_int (Content_identity.byte_length identity));
        replacement;
        (let identity = Content_identity.of_content resulting_content in
         Content_identity.display_hash identity ^ ":"
         ^ string_of_int (Content_identity.byte_length identity));
      ]
  in
  let patch_hash =
    Content_digest.of_content patch_identity |> Content_digest.to_hex
  in
  let* id = Patch_id.make ("patch:derive-sidecar:" ^ String.sub patch_hash 0 24) in
  let* provenance = Provenance.make ~source:"derive:inline-to-sidecar" () in
  Proposed_patch.make ~id ~target:sidecar_path
    ~expected_identity:(Sidecar_snapshot.content_identity sidecar_snapshot)
    ~resulting_identity:(Content_identity.of_content resulting_content)
    ~edits:[ edit ] ~reason:"materialize inline annotations in the sidecar"
    ~provenance

let create_patch ~primary_path ~sidecar_path ~references ~annotations =
  let* content =
    Sidecar_render.new_document ~primary_path ~references ~annotations
  in
  let resulting_identity = Content_identity.of_content content in
  let patch_identity =
    String.concat "\000"
      [
        "inline-to-sidecar";
        "2";
        "create";
        Workspace_path.to_canonical_string sidecar_path;
        content;
        Content_identity.display_hash resulting_identity;
        string_of_int (Content_identity.byte_length resulting_identity);
      ]
  in
  let patch_hash =
    Content_digest.of_content patch_identity |> Content_digest.to_hex
  in
  let* id =
    Patch_id.make ("patch:derive-sidecar:" ^ String.sub patch_hash 0 24)
  in
  let* provenance = Provenance.make ~source:"derive:inline-to-sidecar" () in
  Proposed_patch.make_create ~id ~target:sidecar_path ~resulting_identity
    ~content ~reason:"create the derived sidecar materialization" ~provenance

let no_patch_result ~coverage observations =
  command_result ~termination:Command_result.Completed
    ~effect:Command_result.No_change ~observations
    ~coverage
    ~summary:[ ("patches", Command_result.Count 0) ] ()

let proposed_patch_result ~coverage observations patch =
  command_result ~termination:Command_result.Completed
    ~effect:Command_result.Patches_proposed ~observations
    ~patches:[ patch ]
    ~coverage
    ~summary:[ ("patches", Command_result.Count 1) ] ()

let derived_section_is_current ~primary_path ~sidecar_snapshot ~references
    ~annotations =
  let content = Sidecar_snapshot.bytes sidecar_snapshot in
  let* replacement =
    Sidecar_render.derived_section ~primary_path ~references ~annotations
  in
  let* existing = Sidecar_edit.optional_derived_section_range content in
  match existing with
  | None -> Ok false
  | Some range ->
      let start = Text_range.start range in
      let length = Text_range.length range in
      Ok
        (String.equal replacement
           (String.sub content start length))

let derive_missing_sidecar ~coverage ~observations ~observation ~sidecar_path
    ~candidates ~available_references =
  let references =
    required_reference_ids candidates
    |> select_references available_references
  in
  if candidates = [] then no_patch_result ~coverage observations
  else
    match
      create_patch ~primary_path:observation ~sidecar_path ~references
        ~annotations:candidates
    with
    | Error _ -> internal "construct-sidecar-create-patch"
    | Ok patch -> proposed_patch_result ~coverage observations patch

let derive_existing_sidecar ~coverage ~observations ~observation ~primary_id
    ~sidecar_snapshot ~candidates ~available_references =
  match Sidecar_v2.decode sidecar_snapshot with
  | Error message -> invalid_sidecar ~coverage observations primary_id message
  | Ok sidecar ->
      let expected_scope = Observation.workspace observation in
      if not (Origin.equal expected_scope (Sidecar_contents.scope sidecar)) then
        invalid_sidecar ~coverage observations primary_id
          "Sidecar scope.origin does not match the derive target"
      else
        let references =
          required_reference_ids candidates
          |> select_references available_references
        in
        if candidates = [] && references = [] then
          no_patch_result ~coverage observations
        else
          match
            derived_section_is_current ~primary_path:observation
              ~sidecar_snapshot ~references ~annotations:candidates
          with
          | Error message ->
              invalid_sidecar ~coverage observations primary_id message
          | Ok true -> no_patch_result ~coverage observations
          | Ok false -> (
              match
                patch ~primary_path:observation ~sidecar_snapshot ~references
                  ~annotations:candidates
              with
              | Error message ->
                  invalid_sidecar ~coverage observations primary_id message
              | Ok patch -> proposed_patch_result ~coverage observations patch)

let derive_built_in ~observation snapshot =
  let primary =
    Workspace_graph_snapshot.observations snapshot
    |> List.find_opt (fun candidate ->
           Origin.equal (Observation.origin candidate)
             (Observation.workspace observation))
  in
  match primary with
  | None -> usage "observation does not exist"
  | Some primary -> (
      let coverage = Workspace_graph_snapshot.coverage snapshot in
      let observations = [ primary ] in
      let primary_id = Observation.id primary in
      let candidates, available_references = snapshot_values snapshot primary in
      match Sidecar_path.for_primary observation with
      | Error _ -> internal "construct-sidecar-path"
      | Ok sidecar_path ->
          let sidecar_snapshot =
            Workspace_graph_snapshot.sidecar_snapshots snapshot
            |> List.find_opt (fun candidate ->
                   Workspace_path.compare (Sidecar_snapshot.path candidate)
                     sidecar_path
                   = 0)
          in
          (match sidecar_snapshot with
          | None ->
              derive_missing_sidecar ~coverage ~observations ~observation
                ~sidecar_path ~candidates ~available_references
          | Some sidecar_snapshot ->
              derive_existing_sidecar ~coverage ~observations ~observation
                ~primary_id ~sidecar_snapshot ~candidates
                ~available_references))

let derive_sidecar ~workspace ~observation =
  match Workspace_graph.build_snapshot ~workspace with
  | Error (Workspace_graph.Usage message) -> usage message
  | Error (Workspace_graph.Internal _) -> internal "build-workspace-graph"
  | Ok snapshot -> derive_built_in ~observation snapshot

let extension_failure_result ~coverage ~observations ~capability failure =
  match
    Diagnostic.make ~code:Diagnostic.Extension_failure
      ~message:(Extension_failure.message failure) ~extension_failure:failure ()
  with
  | Error _ -> internal "construct-extension-deriver-diagnostic"
  | Ok diagnostic ->
      command_result ~termination:Command_result.Completed
        ~effect:Command_result.No_change ~observations
        ~capabilities:[ capability ] ~diagnostics:[ diagnostic ]
        ~coverage
        ~summary:[ ("patches", Command_result.Count 0) ] ()

let runtime_failure operation failure =
  Extension_failure.make ~operation
    ~code:(Extension_runtime.failure_code failure)
    ~message:(Extension_runtime.failure_message failure)
    ?data:(Extension_runtime.failure_data failure) ()

let run_extension_deriver ~snapshot ~request extension =
  let manifest = Installed_extension.manifest extension in
  let capability = Installed_extension.capability extension in
  let observations = Workspace_graph_snapshot.observations snapshot in
  let coverage = Workspace_graph_snapshot.coverage snapshot in
  match
    Extension_runtime.with_checked_session
      ~executable:(Installed_extension.executable extension)
      ~arguments:(Installed_extension.arguments extension)
      ~limits:Extension_runtime.default_limits ~manifest (fun session ->
        Extension_runtime.call session ~method_name:"monika.derive"
          ~params:(Extension_protocol.derive_params ~request ~snapshot))
  with
  | Error runtime -> (
      match runtime_failure Extension_failure.Derive runtime with
      | Error _ -> internal "construct-extension-deriver-failure"
      | Ok failure ->
          extension_failure_result ~coverage ~observations ~capability failure)
  | Ok result -> (
      match Extension_protocol.decode_derive_result result with
      | Ok (Extension_protocol.Derived_patches patches) ->
          command_result ~termination:Command_result.Completed
            ~effect:
              (if patches = [] then Command_result.No_change
               else Command_result.Patches_proposed)
            ~observations ~capabilities:[ capability ] ~patches
            ~coverage
            ~summary:[ ("patches", Command_result.Count (List.length patches)) ]
            ()
      | Ok (Extension_protocol.Derive_failure failure) ->
          extension_failure_result ~coverage ~observations ~capability failure
      | Error message -> (
          match
            Extension_failure.make ~operation:Extension_failure.Derive
              ~code:"invalid-extension-result" ~message
              ~data:(`Assoc [ ("decoder", `String "monika.derive") ]) ()
          with
          | Error _ -> internal "construct-invalid-extension-result"
          | Ok failure ->
              extension_failure_result ~coverage ~observations ~capability
                failure))

let derive_with_registry ~workspace ~observation ~registry ~deriver_name
    ~deriver_version =
  match Workspace_graph.build_snapshot_with_registry ~workspace ~registry with
  | Error (Workspace_graph.Usage message) -> usage message
  | Error (Workspace_graph.Internal _) -> internal "build-workspace-graph"
  | Ok snapshot -> (
      match
        Deriver_dispatcher.find_exact registry ~name:deriver_name
          ~version:deriver_version
      with
      | Error message -> usage message
      | Ok None -> usage "requested Deriver is not installed"
      | Ok (Some Deriver_dispatcher.Built_in_inline_to_sidecar) ->
          derive_built_in ~observation snapshot
      | Ok (Some (Deriver_dispatcher.Installed extension)) ->
          run_extension_deriver ~snapshot
            ~request:(Derive_request.inline_to_sidecar observation)
            extension)
