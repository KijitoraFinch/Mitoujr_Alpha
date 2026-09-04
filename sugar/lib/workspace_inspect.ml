let ( let* ) = Result.bind

type inspection = {
  result : Command_result.t;
  content : string option;
  interpretation : Interpretation.t option;
  reference_uses : Reference_use.t list;
  reference_index : Reference_index.t;
  annotation_index : Annotation_index.t;
  relations : Relation.t list;
}

let empty_inspection result =
  {
    result;
    content = None;
    interpretation = None;
    reference_uses = [];
    reference_index = Reference_index.make [];
    annotation_index = Annotation_index.make [];
    relations = [];
  }

let relations ~reference_index annotation_index =
  Annotation_index.entries annotation_index
  |> List.filter_map (fun (_, entry) ->
         Relation.of_index_entry ~reference_index entry)

let complete_inspection ?interpretation ?content ~reference_uses
    ~reference_index ~annotation_index result =
  {
    result;
    content;
    interpretation;
    reference_uses;
    reference_index;
    annotation_index;
    relations = relations ~reference_index annotation_index;
  }

let command_result ?summary ?(diagnostics = []) ?(observations = [])
    ?(sidecar_snapshots = []) ?(regions = []) ?(references = [])
    ?(annotations = []) ?(reference_definitions = []) ?(reference_uses = [])
    ?(annotation_occurrences = []) ?(capabilities = [])
    ?(coverage = Coverage.empty) ~termination () =
  match
    Command_result.make ~command:"inspect" ~termination
      ~effect:Command_result.No_change ~diagnostics ~observations ~regions
      ~sidecar_snapshots ~references ~annotations ~reference_definitions
      ~reference_uses ~annotation_occurrences ~capabilities ~coverage ?summary ()
  with
  | Ok result -> result
  | Error _ ->
      Command_result.internal_error ~command:"inspect"
        ~error_code:"internal-invariant" ~operation:"construct-command-result"

let usage message =
  command_result ~termination:(Command_result.Usage_failure message)
    ~summary:[ ("message", Command_result.Text message) ] ()

let internal ?location operation =
  let summary =
    [
      ("errorCode", Command_result.Text "filesystem-io");
      ("operation", Command_result.Text operation);
    ]
    @
    match location with
    | None -> []
    | Some path ->
        [
          ( "location",
            Command_result.Text (Workspace_path.to_canonical_string path) );
        ]
  in
  command_result
    ~termination:(Command_result.Internal_failure "internal operation failed")
    ~summary ()

let observation_id path =
  Observation_id.make ("observation:" ^ Workspace_path.to_canonical_string path)

let observation observation_type path file =
  let* id = observation_id path in
  Ok
    (Observation.of_bytes ~id ~origin:(Observation.workspace path)
       ~observation_type ~bytes:(Workspace_read.content file))

let whole_region observation =
  let* id =
    Region_id.make ~observation:(Observation.id observation)
      ~local:"whole-observation"
  in
  Ok (Region.whole ~id ~observation_identity:(Observation.identity observation))

let regions_with_whole observation regions =
  let* whole = whole_region observation in
  Ok (whole :: regions)

let diagnostic ~observation_id ~code message =
  Diagnostic.make ~code ~message
    ~location:
      {
        Diagnostic.observation = Some observation_id;
        region = None;
        annotation = None;
        range = None;
      }
    ()

let diagnostic_result ~observations = function
  | Error _ -> internal "construct-diagnostic"
  | Ok diagnostic ->
      command_result ~termination:Command_result.Completed ~observations
        ~diagnostics:[ diagnostic ]
        ~summary:
          [
            ("annotations", Command_result.Count 0);
            ("references", Command_result.Count 0);
            ("regions", Command_result.Count 0);
          ]
        ()

let unsupported_inspection observation message =
  match
    ( whole_region observation,
      diagnostic ~observation_id:(Observation.id observation)
        ~code:Diagnostic.Unsupported_observation message,
      Coverage.make ~primary_resources:1 ~observed:1 ~interpreted:0
        ~unsupported:1 ~failed:0 ~metadata_discovered:0 ~metadata_decoded:0
        ~metadata_failed:0 ~complete:false )
  with
  | Ok region, Ok diagnostic, Ok coverage ->
      let result =
        command_result ~termination:Command_result.Completed
          ~observations:[ observation ] ~regions:[ region ]
          ~diagnostics:[ diagnostic ] ~coverage
          ~summary:
            [
              ("annotations", Command_result.Count 0);
              ("references", Command_result.Count 0);
              ("regions", Command_result.Count 1);
            ]
          ()
      in
      {
        (empty_inspection result) with
        content = Observation.bytes observation;
      }
  | _ -> empty_inspection (internal "construct-unsupported-observation")

let extension_failure_result ?observation_id ~observations ~capabilities
    ~diagnostic_code failure =
  let location =
    Option.map
      (fun observation ->
        {
          Diagnostic.observation = Some observation;
          region = None;
          annotation = None;
          range = None;
        })
      observation_id
  in
  match
    Diagnostic.make ~code:diagnostic_code
      ~message:(Extension_failure.message failure) ?location
      ~extension_failure:failure ()
  with
  | Error _ -> internal "construct-extension-failure-diagnostic"
  | Ok diagnostic -> (
      let regions = List.map whole_region observations in
      match
        List.fold_right
          (fun region result ->
            let* region = region in
            let* regions = result in
            Ok (region :: regions))
          regions (Ok [])
      with
      | Error _ -> internal "construct-whole-region"
      | Ok regions ->
          let primary_resources = List.length observations in
          let unsupported =
            if diagnostic_code = Diagnostic.Unsupported_observation then
              primary_resources
            else 0
          in
          let failed =
            if Diagnostic.effective_severity diagnostic = Diagnostic.Error then
              primary_resources
            else 0
          in
          match
            Coverage.make ~primary_resources ~observed:primary_resources
              ~interpreted:0 ~unsupported ~failed ~metadata_discovered:0
              ~metadata_decoded:0 ~metadata_failed:0
              ~complete:(primary_resources = 0)
          with
          | Error _ -> internal "construct-coverage"
          | Ok coverage ->
              command_result ~termination:Command_result.Completed ~observations
                ~regions ~capabilities ~diagnostics:[ diagnostic ] ~coverage
                ~summary:
                  [
                    ("annotations", Command_result.Count 0);
                    ("references", Command_result.Count 0);
                    ("regions", Command_result.Count (List.length regions));
                  ]
                ())

let runtime_extension_failure operation failure =
  Extension_failure.make ~operation
    ~code:(Extension_runtime.failure_code failure)
    ~message:(Extension_runtime.failure_message failure)
    ?data:(Extension_runtime.failure_data failure) ()

let invalid_extension_result operation message =
  Extension_failure.make ~operation ~code:"invalid-result" ~message ()

let read_primary ~workspace path =
  match Workspace_read.read ~workspace ~path with
  | Ok file -> Ok file
  | Error Workspace_read.Invalid_workspace ->
      Error (`Usage "workspace must be an existing directory")
  | Error Workspace_read.Missing_file ->
      Error (`Usage "observation does not exist")
  | Error (Workspace_read.Unsafe _) ->
      Error (`Usage "observation is outside the safe workspace read policy")
  | Error Workspace_read.Unstable_content -> Error (`Internal "read-stable-observation")
  | Error (Workspace_read.Filesystem_io operation) -> Error (`Internal operation)

let is_markdown_observation observation =
  Observation_type.equal
    (Observation.observation_type observation)
    Observation_type.markdown

let is_jsonl_observation observation =
  let observation_type = Observation.observation_type observation in
  String.equal (Observation_type.name observation_type) "application/x-ndjson"
  && String.equal (Observation_type.version observation_type) "1"

let extension_associated_observation_type manifest path =
  let capability = Extension_manifest.capability manifest in
  match Extension_applicability.associate capability ~path with
  | Error _ as error -> error
  | Ok Extension_applicability.Not_associated ->
      Error "extension does not apply to the selected observation"
  | Ok (Extension_applicability.Associated observation_type) ->
      Ok observation_type

let require_interpreter_manifest manifest =
  let capability = Extension_manifest.capability manifest in
  match Capability.kind capability with
  | Capability.Interpreter -> Ok ()
  | _ -> Error "extension inspect requires an interpreter capability"

let sidecars_for_scope scope snapshots =
  List.fold_left
    (fun (selected, annotations, references) snapshot ->
      match Sidecar_v2.decode snapshot with
      | Error _ -> (selected, annotations, references)
      | Ok contents
        when Origin.equal scope (Sidecar_contents.scope contents) ->
          ( snapshot :: selected,
            List.rev_append
              (Sidecar_contents.annotations contents)
              annotations,
            List.rev_append
              (Sidecar_contents.reference_definitions contents)
              references )
      | Ok _ -> (selected, annotations, references))
    ([], [], []) snapshots
  |> fun (selected, annotations, references) ->
  (List.rev selected, List.rev annotations, List.rev references)

let address_matches_region ~origin address region =
  Origin.equal origin (Region_address.origin address)
  &&
  (match Region_address.selector address with
  | Selector.Region_id local ->
      Identifier.compare local (Region.id region |> Region_id.local) = 0
  | selector -> Selector.compare selector (Region.selector region) = 0)
  &&
  match Region_address.interpreter_identity address with
  | None -> true
  | Some expected -> (
      match Region.interpreter_identity region with
      | Some actual -> Interpreter.equal expected actual
      | None -> false)

let resolve_region_ref ~origin ~regions = function
  | Region_ref.Resolved _ as resolved -> resolved
  | Region_ref.Address address -> (
      match List.find_opt (address_matches_region ~origin address) regions with
      | Some region -> Region_ref.Resolved (Region.id region)
      | None -> Region_ref.Address address)

let resolve_annotation_occurrence ~origin ~regions occurrence =
  let annotation = Annotation_occurrence.annotation occurrence in
  let subject =
    Annotation.subject annotation |> resolve_region_ref ~origin ~regions
  in
  let object_ =
    match Annotation.object_ annotation with
    | Annotation.Region_object region ->
        Annotation.Region_object (resolve_region_ref ~origin ~regions region)
    | Annotation.Reference_object _ as reference -> reference
    | Annotation.Literal _ as literal -> literal
  in
  match
    Annotation.make ~id:(Annotation.id annotation) ~subject
      ~predicate:(Annotation.predicate annotation) ~object_
  with
  | Error _ -> occurrence
  | Ok annotation ->
      Annotation_occurrence.make ~annotation
        ~source:(Annotation_occurrence.source occurrence)

let collect_diagnostics values =
  List.fold_right
    (fun value result ->
      let* value = value in
      let* values = result in
      Ok (value :: values))
    values (Ok [])

let reference_conflict_diagnostics observation index =
  Reference_index.conflicts index
  |> List.map (fun (id, _) ->
         diagnostic ~observation_id:observation ~code:Diagnostic.Divergent
           ("reference " ^ (Reference_id.local id |> Identifier.to_string)
          ^ " has divergent definitions"))
  |> collect_diagnostics

let annotation_conflict_diagnostics observation index =
  Annotation_index.conflicts index
  |> List.map (fun (id, _) ->
         diagnostic ~observation_id:observation ~code:Diagnostic.Divergent
           ("annotation " ^ (Annotation_id.local id |> Identifier.to_string)
          ^ " has divergent occurrences"))
  |> collect_diagnostics

let annotation_reference_diagnostics observation reference_index
    annotation_index =
  Annotation_index.consistent_values annotation_index
  |> List.filter_map (fun annotation ->
         match Annotation.object_ annotation with
         | Annotation.Reference_object id
           when Option.is_none (Reference_index.find id reference_index) ->
             Some
               (diagnostic ~observation_id:observation
                  ~code:Diagnostic.Unresolved_ref
                  ("annotation "
                  ^ (Annotation.id annotation |> Annotation_id.local
                    |> Identifier.to_string)
                  ^ " refers to an undefined reference"))
         | Annotation.Reference_object _
         | Annotation.Region_object _
         | Annotation.Literal _ ->
             None)
  |> collect_diagnostics
let inspect_supported ~primary_observation ~sidecar_snapshots ~base_diagnostics =
  let primary_id = Observation.id primary_observation in
  match Observation.bytes primary_observation with
  | None -> empty_inspection (internal "read-byte-observation")
  | Some content -> (
      match
        Markdown_inspect.inspect ~observation:primary_observation content
      with
      | Error message ->
          empty_inspection
            (diagnostic_result ~observations:[ primary_observation ]
               (diagnostic ~observation_id:primary_id
                  ~code:Diagnostic.Invalid_selector message))
      | Ok markdown ->
          (match
             ( Markdown_interpreter.interpret ~observation:primary_observation
                 ~parsed:markdown,
               Markdown_annotation_extractor.extract
                 ~observation:primary_observation ~parsed:markdown,
               Markdown_reference_extractor.extract
                 ~observation:primary_observation ~parsed:markdown )
           with
          | Error _, _, _ | _, Error _, _ | _, _, Error _ ->
              empty_inspection (internal "construct-markdown-capability-result")
          | Ok interpretation, Ok annotation_extraction,
            Ok reference_extraction ->
          let regions = Interpretation.regions interpretation in
          let selected_sidecars, sidecar_annotations, sidecar_references =
            sidecars_for_scope (Observation.origin primary_observation)
              sidecar_snapshots
          in
          let reference_definitions =
            Reference_extraction.definitions reference_extraction
            @ sidecar_references
          in
          let annotation_occurrences =
            Annotation_extraction.occurrences annotation_extraction
            @ List.map
                (resolve_annotation_occurrence
                   ~origin:(Observation.origin primary_observation)
                   ~regions)
                sidecar_annotations
          in
          let reference_index = Reference_index.make reference_definitions in
          let annotation_index = Annotation_index.make annotation_occurrences in
          (match
             ( reference_conflict_diagnostics primary_id reference_index,
               annotation_conflict_diagnostics primary_id annotation_index,
               annotation_reference_diagnostics primary_id reference_index
                 annotation_index )
           with
          | Error _, _, _ | _, Error _, _ | _, _, Error _ ->
              empty_inspection (internal "construct-index-diagnostic")
          | Ok reference_diagnostics, Ok annotation_diagnostics, Ok use_diagnostics ->
              let diagnostics =
                base_diagnostics @ reference_diagnostics
                @ annotation_diagnostics @ use_diagnostics
              in
              let references = Reference_index.consistent_values reference_index in
              let annotations = Annotation_index.consistent_values annotation_index in
              let metadata_discovered = List.length sidecar_snapshots in
              let metadata_decoded =
                List.fold_left
                  (fun count snapshot ->
                    match Sidecar_v2.decode snapshot with
                    | Ok _ -> count + 1
                    | Error _ -> count)
                  0 sidecar_snapshots
              in
              let metadata_failed = metadata_discovered - metadata_decoded in
              let complete =
                Reference_index.conflicts reference_index = []
                && Annotation_index.conflicts annotation_index = []
                && metadata_failed = 0
              in
              (match
                 Coverage.make ~primary_resources:1 ~observed:1 ~interpreted:1
                   ~unsupported:0 ~failed:0 ~metadata_discovered
                   ~metadata_decoded ~metadata_failed ~complete
               with
              | Error _ -> empty_inspection (internal "construct-coverage")
              | Ok coverage ->
                  let reference_uses =
                    Reference_extraction.uses reference_extraction
                  in
                  let result =
                    command_result ~termination:Command_result.Completed
                      ~observations:[ primary_observation ]
                      ~sidecar_snapshots:selected_sidecars
                      ~regions ~references ~annotations
                      ~reference_definitions
                      ~reference_uses
                      ~annotation_occurrences ~diagnostics ~coverage
                      ~summary:
                        [
                          ("annotationOccurrences",
                           Command_result.Count
                             (List.length annotation_occurrences));
                          ("referenceDefinitions",
                           Command_result.Count
                             (List.length reference_definitions));
                          ("referenceUses",
                           Command_result.Count
                             (List.length reference_uses));
                          ("regions",
                           Command_result.Count (List.length regions));
                        ]
                      ()
                  in
                  complete_inspection ~interpretation ~content
                    ~reference_uses ~reference_index
                    ~annotation_index result))))

let deduplicate_diagnostics diagnostics =
  diagnostics |> List.sort_uniq Diagnostic.compare

let attach_sidecar_metadata ~primary_observation ~sidecar_snapshots
    ~base_diagnostics inspection =
  let selected_sidecars, sidecar_annotations, sidecar_references =
    sidecars_for_scope (Observation.origin primary_observation) sidecar_snapshots
  in
  let regions = Command_result.regions inspection.result in
  let sidecar_annotations =
    List.map
      (resolve_annotation_occurrence
         ~origin:(Observation.origin primary_observation) ~regions)
      sidecar_annotations
  in
  let reference_definitions =
    Command_result.reference_definitions inspection.result @ sidecar_references
  in
  let annotation_occurrences =
    Command_result.annotation_occurrences inspection.result @ sidecar_annotations
  in
  let reference_index = Reference_index.make reference_definitions in
  let annotation_index = Annotation_index.make annotation_occurrences in
  match
    ( reference_conflict_diagnostics (Observation.id primary_observation)
        reference_index,
      annotation_conflict_diagnostics (Observation.id primary_observation)
        annotation_index,
      annotation_reference_diagnostics (Observation.id primary_observation)
        reference_index annotation_index )
  with
  | Error _, _, _ | _, Error _, _ | _, _, Error _ ->
      empty_inspection (internal "construct-index-diagnostic")
  | Ok reference_diagnostics, Ok annotation_diagnostics, Ok use_diagnostics ->
      let diagnostics =
        base_diagnostics @ Command_result.diagnostics inspection.result
        @ reference_diagnostics @ annotation_diagnostics @ use_diagnostics
        |> deduplicate_diagnostics
      in
      let references = Reference_index.consistent_values reference_index in
      let annotations = Annotation_index.consistent_values annotation_index in
      let metadata_discovered = List.length sidecar_snapshots in
      let metadata_decoded =
        List.fold_left
          (fun count snapshot ->
            match Sidecar_v2.decode snapshot with
            | Ok _ -> count + 1
            | Error _ -> count)
          0 sidecar_snapshots
      in
      let metadata_failed = metadata_discovered - metadata_decoded in
      let unsupported =
        if
          List.exists
            (fun diagnostic ->
              Diagnostic.code diagnostic = Diagnostic.Unsupported_observation)
            diagnostics
        then 1
        else 0
      in
      let failed =
        if
          List.exists
            (fun diagnostic ->
              Diagnostic.effective_severity diagnostic = Diagnostic.Error)
            diagnostics
        then 1
        else 0
      in
      let interpreted =
        match inspection.interpretation with Some _ -> 1 | None -> 0
      in
      let complete =
        unsupported = 0 && failed = 0 && metadata_failed = 0
        && Reference_index.conflicts reference_index = []
        && Annotation_index.conflicts annotation_index = []
      in
      (match
         Coverage.make ~primary_resources:1 ~observed:1 ~interpreted
           ~unsupported ~failed ~metadata_discovered ~metadata_decoded
           ~metadata_failed ~complete
       with
      | Error _ -> empty_inspection (internal "construct-coverage")
      | Ok coverage ->
          let result =
            command_result ~termination:Command_result.Completed
              ~observations:[ primary_observation ] ~sidecar_snapshots:selected_sidecars
              ~regions ~references ~annotations ~reference_definitions
              ~reference_uses:inspection.reference_uses ~annotation_occurrences
              ~diagnostics
              ~capabilities:(Command_result.capabilities inspection.result)
              ~coverage
              ~summary:
                [
                  ( "annotationOccurrences",
                    Command_result.Count (List.length annotation_occurrences) );
                  ( "referenceDefinitions",
                    Command_result.Count (List.length reference_definitions) );
                  ( "referenceUses",
                    Command_result.Count (List.length inspection.reference_uses) );
                  ("regions", Command_result.Count (List.length regions));
                ]
              ()
          in
          {
            inspection with
            result;
            reference_index;
            annotation_index;
            relations = relations ~reference_index annotation_index;
          })

let inspect_whole_observation ~interpreter ~primary_observation =
  match
    ( Observation.bytes primary_observation,
      regions_with_whole primary_observation [] )
  with
  | None, _ -> empty_inspection (internal "read-byte-observation")
  | _, Error _ -> empty_inspection (internal "construct-whole-region")
  | Some content, Ok regions -> (
      match
        Interpretation.make ~interpreter ~observation:primary_observation ~regions
      with
      | Error _ -> empty_inspection (internal "construct-interpretation")
      | Ok interpretation ->
          let coverage =
            Coverage.make ~primary_resources:1 ~observed:1 ~interpreted:1
              ~unsupported:0 ~failed:0 ~metadata_discovered:0
              ~metadata_decoded:0 ~metadata_failed:0 ~complete:true
          in
          (match coverage with
          | Error _ -> empty_inspection (internal "construct-coverage")
          | Ok coverage ->
              let result =
                command_result ~termination:Command_result.Completed
                  ~observations:[ primary_observation ] ~regions ~coverage
                  ~summary:
                    [
                      ("annotationOccurrences", Command_result.Count 0);
                      ("referenceDefinitions", Command_result.Count 0);
                      ("referenceUses", Command_result.Count 0);
                      ("regions", Command_result.Count (List.length regions));
                    ]
                  ()
              in
              complete_inspection ~interpretation ~content ~reference_uses:[]
                ~reference_index:(Reference_index.make [])
                ~annotation_index:(Annotation_index.make []) result))
let inspect_observation ~workspace ~observation:observation_path =
  let scanned = Workspace_scan.scan ~workspace in
  match Command_result.termination scanned with
  | Command_result.Usage_failure message -> empty_inspection (usage message)
  | Command_result.Internal_failure _ ->
      empty_inspection (internal "scan-workspace")
  | Command_result.Completed ->
      let observations = Command_result.observations scanned in
      let selected =
        List.find_opt
          (fun observation ->
            match Observation.origin observation with
            | Origin.Workspace path -> Workspace_path.equal path observation_path
            | Origin.Git _
            | Origin.Web _
            | Origin.Generated _
            | Origin.External _
            | Origin.Extension _ ->
                false)
          observations
      in
      (match selected with
      | None ->
          if
            List.exists
              (fun snapshot ->
                Workspace_path.equal
                  (Sidecar_snapshot.path snapshot)
                  observation_path)
              (Command_result.sidecar_snapshots scanned)
          then
            empty_inspection
              (usage
                 "reserved Sidecar metadata is not a primary Resource observation")
          else empty_inspection (usage "observation does not exist")
      | Some primary_observation ->
          let primary =
            if is_markdown_observation primary_observation then
              inspect_supported ~primary_observation
                ~sidecar_snapshots:[] ~base_diagnostics:[]
            else if is_jsonl_observation primary_observation then
              match Interpreter.make ~name:"jsonl" ~version:"1" () with
              | Error _ ->
                  empty_inspection (internal "construct-jsonl-interpreter")
              | Ok interpreter ->
                  inspect_whole_observation ~interpreter
                    ~primary_observation
            else
              unsupported_inspection primary_observation
                "no standard interpreter supports this observation"
          in
          attach_sidecar_metadata ~primary_observation
            ~sidecar_snapshots:(Command_result.sidecar_snapshots scanned)
            ~base_diagnostics:(Command_result.diagnostics scanned) primary)
type existing_observation_error =
  | Observation_changed
  | Invalid_observation of string

let read_existing_observation ~workspace observation =
  match Observation.origin observation with
  | Origin.Workspace path -> (
      match Observation.content_identity observation with
      | None ->
          Error
            (Invalid_observation
               "workspace observation must have a content identity")
      | Some expected -> (
          match read_primary ~workspace path with
          | Error (`Usage message) ->
              Ok (path, Error (empty_inspection (usage message)))
          | Error (`Internal operation) ->
              Ok
                ( path,
                  Error
                    (empty_inspection
                       (internal ~location:path operation)) )
          | Ok file ->
              if
                Content_identity.equal expected
                  (Workspace_read.content_identity file)
              then Ok (path, Ok file)
              else Error Observation_changed))
  | Origin.Git _
  | Origin.Web _
  | Origin.Generated _
  | Origin.External _
  | Origin.Extension _ ->
      Error
        (Invalid_observation
           "workspace inspection requires a workspace observation origin")

let inspect_fixed_observation ~observation ~sidecar_snapshots ~base_diagnostics =
  let primary =
    if is_markdown_observation observation then
      inspect_supported ~primary_observation:observation ~sidecar_snapshots:[]
        ~base_diagnostics:[]
    else if is_jsonl_observation observation then
      match Interpreter.make ~name:"jsonl" ~version:"1" () with
      | Error _ -> empty_inspection (internal "construct-jsonl-interpreter")
      | Ok interpreter ->
          inspect_whole_observation ~interpreter ~primary_observation:observation
    else
      unsupported_inspection observation
        "no standard interpreter supports this observation"
  in
  Ok
    (attach_sidecar_metadata ~primary_observation:observation ~sidecar_snapshots
       ~base_diagnostics primary)

let inspect_existing_observation ~workspace ~observation =
  match read_existing_observation ~workspace observation with
  | Error _ as error -> error
  | Ok (_, Error inspection) -> Ok inspection
  | Ok (_path, Ok _file) ->
      let scanned = Workspace_scan.scan ~workspace in
      (match Command_result.termination scanned with
      | Command_result.Completed ->
          inspect_fixed_observation ~observation
            ~sidecar_snapshots:(Command_result.sidecar_snapshots scanned)
            ~base_diagnostics:(Command_result.diagnostics scanned)
      | Command_result.Usage_failure message ->
          Ok (empty_inspection (usage message))
      | Command_result.Internal_failure _ ->
          Ok (empty_inspection (internal "scan-workspace")))

let call_with_observation session ~method_name ~params observation =
  match Observation.bytes observation with
  | Some content ->
      Extension_runtime.call_with_content session ~method_name ~params ~content
  | None -> Extension_runtime.call session ~method_name ~params

let interpret_extension_observation ~primary_observation ~manifest ~session =
  let params =
    Extension_protocol.interpret_params
      ~observation:primary_observation
  in
  match
    call_with_observation session ~method_name:"monika.interpretObservation"
      ~params primary_observation
  with
  | Error failure ->
      empty_inspection
        (match
           runtime_extension_failure Extension_failure.Interpret_observation
             failure
         with
        | Error _ -> internal "construct-extension-runtime-failure"
        | Ok failure ->
            extension_failure_result
              ~observation_id:(Observation.id primary_observation)
              ~observations:[ primary_observation ]
              ~capabilities:[ Extension_manifest.capability manifest ]
              ~diagnostic_code:Diagnostic.Extension_failure failure)
  | Ok result -> (
      match
        Extension_protocol.decode_interpret_result ~manifest
          ~primary_observation result
      with
      | Error message ->
          empty_inspection
            (match
               invalid_extension_result Extension_failure.Interpret_observation
                 message
             with
            | Error _ -> internal "construct-invalid-extension-result"
            | Ok failure ->
                extension_failure_result
                  ~observation_id:(Observation.id primary_observation)
                  ~observations:[ primary_observation ]
                  ~capabilities:[ Extension_manifest.capability manifest ]
                  ~diagnostic_code:Diagnostic.Extension_failure failure)
      | Ok
          (Extension_protocol.Interpret_failure failure) ->
          let diagnostic_code =
            if
              String.equal (Extension_failure.code failure)
                "unsupported-observation"
            then Diagnostic.Unsupported_observation
            else Diagnostic.Extension_failure
          in
          empty_inspection
            (extension_failure_result
               ~observation_id:(Observation.id primary_observation)
               ~observations:[ primary_observation ]
               ~capabilities:[ Extension_manifest.capability manifest ]
               ~diagnostic_code failure)
      | Ok
          (Extension_protocol.Interpretation interpretation) ->
          let regions =
            regions_with_whole primary_observation
              (Interpretation.regions interpretation)
          in
          (match regions with
          | Error _ -> empty_inspection (internal "construct-whole-region")
          | Ok regions ->
          let interpretation =
            Interpretation.make
              ~interpreter:(Interpretation.interpreter interpretation)
              ~observation:primary_observation ~regions
          in
          (match interpretation with
          | Error _ -> empty_inspection (internal "construct-interpretation")
          | Ok interpretation ->
          let coverage =
            Coverage.make ~primary_resources:1 ~observed:1 ~interpreted:1
              ~unsupported:0 ~failed:0 ~metadata_discovered:0
              ~metadata_decoded:0 ~metadata_failed:0 ~complete:true
          in
          (match coverage with
          | Error _ -> empty_inspection (internal "construct-coverage")
          | Ok coverage ->
          let result =
            command_result ~termination:Command_result.Completed
              ~observations:[ primary_observation ] ~regions
              ~capabilities:[ Extension_manifest.capability manifest ]
              ~coverage
              ~summary:
                [
                  ("annotations", Command_result.Count 0);
                  ("references", Command_result.Count 0);
                  ("regions", Command_result.Count (List.length regions));
                  ("runtimeChecked", Command_result.Flag true);
                ]
              ()
          in
          complete_inspection ~interpretation
            ?content:(Observation.bytes primary_observation) ~reference_uses:[]
            ~reference_index:(Reference_index.make [])
            ~annotation_index:(Annotation_index.make []) result))))

let inspect_fixed_observation_with_extension_session ~observation ~manifest
    ~session =
  let capability = Extension_manifest.capability manifest in
  match require_interpreter_manifest manifest with
  | Error message -> Error (Invalid_observation message)
  | Ok () -> (
      match Extension_applicability.accepts capability ~observation with
      | Error message -> Error (Invalid_observation message)
      | Ok false ->
          Error
            (Invalid_observation
               "extension does not accept the fixed observation")
      | Ok true ->
          Ok
            (interpret_extension_observation
               ~primary_observation:observation ~manifest ~session))

let inspect_existing_observation_with_extension_session ~workspace
    ~observation ~manifest ~session =
  match read_existing_observation ~workspace observation with
  | Error _ as error -> error
  | Ok (_, Error inspection) -> Ok inspection
  | Ok (_, Ok _file) ->
      inspect_fixed_observation_with_extension_session ~observation ~manifest
        ~session

let inspect_observation_with_extension_session ~workspace
    ~observation:observation_path ~manifest ~session =
  match
    ( require_interpreter_manifest manifest,
      extension_associated_observation_type manifest observation_path )
  with
  | Error message, _ | _, Error message -> empty_inspection (usage message)
  | Ok (), Ok observation_type -> (
      match read_primary ~workspace observation_path with
      | Error (`Usage message) -> empty_inspection (usage message)
      | Error (`Internal operation) ->
          empty_inspection (internal ~location:observation_path operation)
      | Ok primary_file -> (
          match observation observation_type observation_path primary_file with
          | Error _ ->
              empty_inspection (internal "construct-primary-observation")
          | Ok primary_observation ->
              interpret_extension_observation ~primary_observation ~manifest
                ~session))

let inspect_with_extension_session ~workspace ~observation ~manifest ~session =
  (inspect_observation_with_extension_session ~workspace ~observation ~manifest
     ~session)
    .result

let inspect_observation_with_extension ~workspace ~observation ~manifest
    ~executable ~arguments ~authority =
  match
    ( require_interpreter_manifest manifest,
      extension_associated_observation_type manifest observation )
  with
  | Error message, _ | _, Error message -> empty_inspection (usage message)
  | Ok (), Ok _ -> (
      match
        Extension_runtime.with_checked_session ~executable ~arguments
          ~authority
          ~limits:Extension_runtime.default_limits ~manifest (fun session ->
            Ok
              (inspect_observation_with_extension_session ~workspace ~observation
                 ~manifest
                 ~session))
      with
      | Ok result -> result
      | Error failure ->
          (match runtime_extension_failure Extension_failure.Session failure with
          | Error _ ->
              empty_inspection (internal "construct-extension-session-failure")
          | Ok failure ->
              extension_failure_result ~observations:[]
                ~capabilities:[ Extension_manifest.capability manifest ]
                ~diagnostic_code:Diagnostic.Extension_failure failure
              |> empty_inspection))

let inspect_with_extension ~workspace ~observation ~manifest ~executable
    ~arguments ~authority =
  (inspect_observation_with_extension ~workspace ~observation ~manifest
     ~executable ~arguments ~authority)
    .result

let inspect_existing_observation_with_installed_extension ~workspace
    ~observation ~extension =
  let manifest = Installed_extension.manifest extension in
  match
    Extension_runtime.with_checked_session
      ~executable:(Installed_extension.executable extension)
      ~arguments:(Installed_extension.arguments extension)
      ~authority:(Installed_extension.authority extension)
      ~limits:Extension_runtime.default_limits ~manifest (fun session ->
        inspect_existing_observation_with_extension_session ~workspace
          ~observation ~manifest ~session
        |> function
        | Ok inspection -> Ok (`Inspection inspection)
        | Error error -> Ok (`Existing_error error))
  with
  | Ok (`Inspection inspection) -> Ok inspection
  | Ok (`Existing_error error) -> Error error
  | Error runtime_failure ->
      let result =
        match runtime_extension_failure Extension_failure.Session runtime_failure with
        | Error _ -> internal "construct-extension-session-failure"
        | Ok failure ->
            extension_failure_result ~observations:[ observation ]
              ~capabilities:[ Installed_extension.capability extension ]
              ~diagnostic_code:Diagnostic.Extension_failure failure
      in
      Ok (empty_inspection result)

let inspect_fixed_observation_with_installed_extension ~observation ~extension =
  let manifest = Installed_extension.manifest extension in
  match
    Extension_runtime.with_checked_session
      ~executable:(Installed_extension.executable extension)
      ~arguments:(Installed_extension.arguments extension)
      ~authority:(Installed_extension.authority extension)
      ~limits:Extension_runtime.default_limits ~manifest (fun session ->
        inspect_fixed_observation_with_extension_session ~observation ~manifest
          ~session
        |> function
        | Ok inspection -> Ok (`Inspection inspection)
        | Error error -> Ok (`Existing_error error))
  with
  | Ok (`Inspection inspection) -> Ok inspection
  | Ok (`Existing_error error) -> Error error
  | Error runtime_failure ->
      let result =
        match runtime_extension_failure Extension_failure.Session runtime_failure with
        | Error _ -> internal "construct-extension-session-failure"
        | Ok failure ->
            extension_failure_result ~observations:[ observation ]
              ~capabilities:[ Installed_extension.capability extension ]
              ~diagnostic_code:Diagnostic.Extension_failure failure
      in
      Ok (empty_inspection result)

let run_annotation_extractor ~observation ~interpretation extension =
  let manifest = Installed_extension.manifest extension in
  match
    Extension_runtime.with_checked_session
      ~executable:(Installed_extension.executable extension)
      ~arguments:(Installed_extension.arguments extension)
      ~authority:(Installed_extension.authority extension)
      ~limits:Extension_runtime.default_limits ~manifest (fun session ->
        let params =
          Extension_protocol.extract_annotations_params ~observation
            ~interpretation
        in
        call_with_observation session ~method_name:"monika.extractAnnotations"
          ~params observation)
  with
  | Error failure ->
      runtime_extension_failure Extension_failure.Extract_annotations failure
      |> Result.map_error (fun _ -> "construct annotation extractor failure")
      |> Result.map (fun failure -> Error failure)
  | Ok result -> (
      match
        Extension_protocol.decode_extract_annotations_result
          ~primary_observation:observation result
      with
      | Ok (Extension_protocol.Annotation_extraction extraction) ->
          Ok (Ok extraction)
      | Ok
          (Extension_protocol.Extract_annotations_failure failure) ->
          Ok (Error failure)
      | Error message ->
          invalid_extension_result Extension_failure.Extract_annotations message
          |> Result.map_error (fun _ -> "construct invalid extractor result")
          |> Result.map (fun failure -> Error failure))

let run_reference_extractor ~observation ~interpretation extension =
  let manifest = Installed_extension.manifest extension in
  match
    Extension_runtime.with_checked_session
      ~executable:(Installed_extension.executable extension)
      ~arguments:(Installed_extension.arguments extension)
      ~authority:(Installed_extension.authority extension)
      ~limits:Extension_runtime.default_limits ~manifest (fun session ->
        let params =
          Extension_protocol.extract_references_params ~observation
            ~interpretation
        in
        call_with_observation session ~method_name:"monika.extractReferences"
          ~params observation)
  with
  | Error failure ->
      runtime_extension_failure Extension_failure.Extract_references failure
      |> Result.map_error (fun _ -> "construct reference extractor failure")
      |> Result.map (fun failure -> Error failure)
  | Ok result -> (
      match
        Extension_protocol.decode_extract_references_result
          ~primary_observation:observation result
      with
      | Ok (Extension_protocol.Reference_extraction extraction) ->
          Ok (Ok extraction)
      | Ok
          (Extension_protocol.Extract_references_failure failure) ->
          Ok (Error failure)
      | Error message ->
          invalid_extension_result Extension_failure.Extract_references message
          |> Result.map_error (fun _ -> "construct invalid extractor result")
          |> Result.map (fun failure -> Error failure))

let extractor_diagnostic observation failure =
  Diagnostic.make ~code:Diagnostic.Extension_failure
    ~message:(Extension_failure.message failure)
    ~location:
      {
        Diagnostic.observation = Some (Observation.id observation);
        region = None;
        annotation = None;
        range = None;
      }
    ~extension_failure:failure ()

let coverage_with_diagnostics coverage diagnostics =
  let has_error =
    List.exists
      (fun diagnostic ->
        Diagnostic.effective_severity diagnostic = Diagnostic.Error)
      diagnostics
  in
  let failed =
    if has_error then max 1 (Coverage.failed coverage)
    else Coverage.failed coverage
  in
  Coverage.make ~primary_resources:(Coverage.primary_resources coverage)
    ~observed:(Coverage.observed coverage)
    ~interpreted:(Coverage.interpreted coverage)
    ~unsupported:(Coverage.unsupported coverage) ~failed
    ~metadata_discovered:(Coverage.metadata_discovered coverage)
    ~metadata_decoded:(Coverage.metadata_decoded coverage)
    ~metadata_failed:(Coverage.metadata_failed coverage)
    ~complete:(Coverage.complete coverage && not has_error)

let coverage_with_final_indexes coverage diagnostics reference_index
    annotation_index =
  let has_error =
    List.exists
      (fun diagnostic ->
        Diagnostic.effective_severity diagnostic = Diagnostic.Error)
      diagnostics
  in
  let failed =
    if has_error then max 1 (Coverage.failed coverage) else 0
  in
  let primary_resources = Coverage.primary_resources coverage in
  let observed = Coverage.observed coverage in
  let metadata_discovered = Coverage.metadata_discovered coverage in
  let metadata_decoded = Coverage.metadata_decoded coverage in
  let metadata_failed = Coverage.metadata_failed coverage in
  let complete =
    observed = primary_resources
    && Coverage.unsupported coverage = 0
    && failed = 0
    && metadata_decoded + metadata_failed = metadata_discovered
    && metadata_failed = 0
    && Reference_index.conflicts reference_index = []
    && Annotation_index.conflicts annotation_index = []
  in
  Coverage.make ~primary_resources ~observed
    ~interpreted:(Coverage.interpreted coverage)
    ~unsupported:(Coverage.unsupported coverage) ~failed ~metadata_discovered
    ~metadata_decoded ~metadata_failed ~complete

let contains_region regions id =
  List.exists (fun region -> Region_id.equal id (Region.id region)) regions

let validate_annotation_extraction ~regions extraction =
  let validate_region_ref = function
    | Region_ref.Address _ -> true
    | Region_ref.Resolved id -> contains_region regions id
  in
  let valid_occurrence occurrence =
    let annotation = Annotation_occurrence.annotation occurrence in
    validate_region_ref (Annotation.subject annotation)
    &&
    match Annotation.object_ annotation with
    | Annotation.Region_object region -> validate_region_ref region
    | Annotation.Reference_object _ | Annotation.Literal _ -> true
  in
  if
    List.for_all valid_occurrence
      (Annotation_extraction.occurrences extraction)
  then Ok ()
  else
    Error
      "annotation extraction contains a resolved Region that is not available for the input Observation"

let validate_reference_extraction ~regions extraction =
  let valid_use use =
    match Reference_use.source_region use with
    | Reference_use.Whole_observation -> true
    | Reference_use.Region id -> contains_region regions id
  in
  if List.for_all valid_use (Reference_extraction.uses extraction) then Ok ()
  else
    Error
      "reference extraction contains a source Region that is not available for the input Observation"

let validate_extraction_result ~operation validate = function
  | Error failure -> Ok (Error failure)
  | Ok extraction -> (
      match validate extraction with
      | Ok () -> Ok (Ok extraction)
      | Error message ->
          invalid_extension_result operation message
          |> Result.map_error (fun _ -> "construct invalid extractor result")
          |> Result.map (fun failure -> Error failure))

let apply_annotation_extractors ~registry ~observation inspection =
  let interpretation = inspection.interpretation in
  let regions = Command_result.regions inspection.result in
  let* extractors =
    Annotation_extractor_dispatcher.select_all registry observation
  in
  let* occurrences, diagnostics, capabilities =
    List.fold_left
      (fun result extension ->
        let* occurrences, diagnostics, capabilities = result in
        let capability = Installed_extension.capability extension in
        let* extraction =
          run_annotation_extractor ~observation ~interpretation extension
        in
        let* extraction =
          validate_extraction_result
            ~operation:Extension_failure.Extract_annotations
            (validate_annotation_extraction ~regions)
            extraction
        in
        match extraction with
        | Ok extraction ->
            Ok
              ( Annotation_extraction.occurrences extraction
                |> List.rev_append occurrences,
                diagnostics,
                capability :: capabilities )
        | Error failure ->
            let* diagnostic = extractor_diagnostic observation failure in
            Ok
              ( occurrences,
                diagnostic :: diagnostics,
                capability :: capabilities ))
      (Ok ([], [], [])) extractors
  in
  let occurrences = List.rev occurrences in
  let diagnostics =
    List.rev_append diagnostics (Command_result.diagnostics inspection.result)
  in
  let capabilities =
    List.rev_append capabilities (Command_result.capabilities inspection.result)
  in
  let annotation_occurrences =
    Command_result.annotation_occurrences inspection.result @ occurrences
  in
  let annotation_index = Annotation_index.make annotation_occurrences in
  let annotations = Annotation_index.consistent_values annotation_index in
  let* conflict_diagnostics =
    annotation_conflict_diagnostics (Observation.id observation)
      annotation_index
  in
  let diagnostics =
    diagnostics @ conflict_diagnostics |> deduplicate_diagnostics
  in
  let* coverage =
    coverage_with_diagnostics (Command_result.coverage inspection.result)
      diagnostics
  in
  let result =
    command_result ~termination:Command_result.Completed
      ~observations:(Command_result.observations inspection.result)
      ~sidecar_snapshots:(Command_result.sidecar_snapshots inspection.result)
      ~regions ~references:(Command_result.references inspection.result)
      ~annotations
      ~reference_definitions:
        (Command_result.reference_definitions inspection.result)
      ~reference_uses:inspection.reference_uses ~annotation_occurrences
      ~diagnostics ~capabilities ~coverage
      ~summary:
        [
          ("annotations", Command_result.Count (List.length annotations));
          ( "references",
            Command_result.Count
              (Command_result.references inspection.result |> List.length) );
          ("regions", Command_result.Count (List.length regions));
          ("runtimeChecked", Command_result.Flag true);
        ]
      ()
  in
  Ok
    {
      inspection with
      result;
      annotation_index;
      relations =
        relations ~reference_index:inspection.reference_index annotation_index;
    }

let apply_reference_extractors ~registry ~observation inspection =
  let interpretation = inspection.interpretation in
  let regions = Command_result.regions inspection.result in
  let* extractors =
    Reference_extractor_dispatcher.select_all registry observation
  in
  let* definitions, uses, diagnostics, capabilities =
    List.fold_left
      (fun result extension ->
        let* definitions, uses, diagnostics, capabilities = result in
        let capability = Installed_extension.capability extension in
        let capabilities = capability :: capabilities in
        let* extraction =
          run_reference_extractor ~observation ~interpretation extension
        in
        let* extraction =
          validate_extraction_result
            ~operation:Extension_failure.Extract_references
            (validate_reference_extraction ~regions)
            extraction
        in
        match extraction with
        | Ok extraction ->
            Ok
              ( Reference_extraction.definitions extraction
                |> List.rev_append definitions,
                Reference_extraction.uses extraction |> List.rev_append uses,
                diagnostics,
                capabilities )
        | Error failure ->
            let* diagnostic = extractor_diagnostic observation failure in
            Ok (definitions, uses, diagnostic :: diagnostics, capabilities))
      (Ok ([], [], [], [])) extractors
  in
  let definitions = List.rev definitions in
  let uses = List.rev uses in
  let diagnostics =
    List.rev_append diagnostics (Command_result.diagnostics inspection.result)
  in
  let capabilities =
    List.rev_append capabilities (Command_result.capabilities inspection.result)
  in
  let reference_definitions =
    Command_result.reference_definitions inspection.result @ definitions
  in
  let reference_index = Reference_index.make reference_definitions in
  let references = Reference_index.consistent_values reference_index in
  let reference_uses = inspection.reference_uses @ uses in
  let* conflict_diagnostics =
    reference_conflict_diagnostics (Observation.id observation) reference_index
  in
  let* annotation_diagnostics =
    annotation_conflict_diagnostics (Observation.id observation)
      inspection.annotation_index
  in
  let* use_diagnostics =
    annotation_reference_diagnostics (Observation.id observation) reference_index
      inspection.annotation_index
  in
  let diagnostics =
    List.filter
      (fun diagnostic ->
        match Diagnostic.code diagnostic with
        | Diagnostic.Divergent | Diagnostic.Unresolved_ref -> false
        | _ -> true)
      diagnostics
  in
  let diagnostics =
    diagnostics @ conflict_diagnostics @ annotation_diagnostics @ use_diagnostics
    |> deduplicate_diagnostics
  in
  let* coverage =
    coverage_with_final_indexes (Command_result.coverage inspection.result)
      diagnostics reference_index inspection.annotation_index
  in
  let result =
    command_result ~termination:Command_result.Completed
      ~observations:(Command_result.observations inspection.result)
      ~sidecar_snapshots:(Command_result.sidecar_snapshots inspection.result)
      ~regions ~references
      ~annotations:(Command_result.annotations inspection.result)
      ~reference_definitions ~reference_uses
      ~annotation_occurrences:
        (Command_result.annotation_occurrences inspection.result)
      ~diagnostics ~capabilities ~coverage
      ~summary:
        [
          ( "annotations",
            Command_result.Count
              (Command_result.annotations inspection.result |> List.length) );
          ("references", Command_result.Count (List.length references));
          ("regions", Command_result.Count (List.length regions));
          ("runtimeChecked", Command_result.Flag true);
        ]
      ()
  in
  Ok
    {
      inspection with
      result;
      reference_uses;
      reference_index;
      relations = relations ~reference_index inspection.annotation_index;
    }

let apply_extractors ~registry ~observation inspection =
  let* inspection =
    apply_annotation_extractors ~registry ~observation inspection
  in
  apply_reference_extractors ~registry ~observation inspection

let inspect_fixed_observation_with_registry ~observation ~sidecar_snapshots
    ~base_diagnostics ~registry =
  match Interpreter_dispatcher.select registry observation with
  | Error message -> Error (Invalid_observation message)
  | Ok None ->
      let primary =
        unsupported_inspection observation
          "no installed interpreter supports this observation"
      in
      let inspection =
        attach_sidecar_metadata ~primary_observation:observation
          ~sidecar_snapshots ~base_diagnostics primary
      in
      apply_extractors ~registry ~observation inspection
      |> Result.map_error (fun message -> Invalid_observation message)
  | Ok
      (Some
        (Interpreter_dispatcher.Built_in_markdown
        | Interpreter_dispatcher.Built_in_jsonl)) ->
      let* inspection =
        inspect_fixed_observation ~observation ~sidecar_snapshots
          ~base_diagnostics
      in
      apply_extractors ~registry ~observation inspection
      |> Result.map_error (fun message -> Invalid_observation message)
  | Ok (Some (Interpreter_dispatcher.Installed extension)) ->
      let* inspection =
        inspect_fixed_observation_with_installed_extension ~observation ~extension
      in
      let* inspection =
        apply_extractors ~registry ~observation inspection
        |> Result.map_error (fun message -> Invalid_observation message)
      in
      Ok
        (attach_sidecar_metadata ~primary_observation:observation
           ~sidecar_snapshots ~base_diagnostics inspection)

let inspect_existing_observation_with_registry ~workspace ~observation
    ~registry =
  match read_existing_observation ~workspace observation with
  | Error _ as error -> error
  | Ok (_, Error inspection) -> Ok inspection
  | Ok (_, Ok _file) ->
      let scanned =
        Workspace_scan.scan_with_classifier ~workspace
          ~classify:(Interpreter_dispatcher.classify_path registry)
      in
      (match Command_result.termination scanned with
      | Command_result.Completed ->
          inspect_fixed_observation_with_registry ~observation
            ~sidecar_snapshots:(Command_result.sidecar_snapshots scanned)
            ~base_diagnostics:(Command_result.diagnostics scanned) ~registry
      | Command_result.Usage_failure message ->
          Ok (empty_inspection (usage message))
      | Command_result.Internal_failure _ ->
          Ok (empty_inspection (internal "scan-workspace")))

let inspect_observation_with_registry ~workspace
    ~observation:observation_path ~registry =
  match Interpreter_dispatcher.classify_path registry observation_path with
  | Error message -> empty_inspection (usage message)
  | Ok observation_type -> (
      match read_primary ~workspace observation_path with
      | Error (`Usage message) -> empty_inspection (usage message)
      | Error (`Internal operation) ->
          empty_inspection (internal ~location:observation_path operation)
      | Ok primary_file -> (
          match observation observation_type observation_path primary_file with
          | Error _ -> empty_inspection (internal "construct-primary-observation")
          | Ok primary_observation -> (
              match
                inspect_existing_observation_with_registry ~workspace
                  ~observation:primary_observation ~registry
              with
              | Ok inspection -> inspection
              | Error Observation_changed ->
                  empty_inspection
                    (internal "observation-changed-during-inspection")
              | Error (Invalid_observation message) ->
                  empty_inspection (usage message))))

let inspect_with_registry ~workspace ~observation ~registry =
  (inspect_observation_with_registry ~workspace ~observation ~registry).result

let inspect ~workspace ~observation =
  (inspect_observation ~workspace ~observation).result
