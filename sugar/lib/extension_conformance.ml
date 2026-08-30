type failure =
  | Session_runtime of Extension_runtime.failure
  | Method_runtime of {
      operation : Extension_failure.operation;
      method_name : string;
      failure : Extension_runtime.failure;
    }
  | Invalid_result of {
      operation : Extension_failure.operation;
      method_name : string;
      message : string;
    }

let ( let* ) = Result.bind

let runtime ~operation ~method_name result =
  Result.map_error
    (fun failure -> Method_runtime { operation; method_name; failure })
    result

let decode ~operation ~method_name result =
  Result.map_error
    (fun message -> Invalid_result { operation; method_name; message })
    result

let conformance_observation capability =
  let observation_type =
    match Capability.applies_to capability with
    | Some { observation_types = first :: _; _ } -> first
    | Some { observation_types = []; _ } | None -> Observation_type.binary
  in
  let* origin = Observation.generated "monika:extension-conformance" in
  let* id = Observation_id.make "observation:extension-conformance" in
  Ok
    (Observation.of_bytes ~id ~origin ~observation_type
       ~bytes:"monika extension conformance")

let conformance_region observation interpreter local selector =
  let* id = Region_id.make ~observation:(Observation.id observation) ~local in
  Region.make ~id ~observation_identity:(Observation.identity observation)
    ~selector ~interpreter ()

let call_with_observation session ~method_name ~params observation =
  match Observation.bytes observation with
  | Some content ->
      Extension_runtime.call_with_content session ~method_name ~params ~content
  | None -> Extension_runtime.call session ~method_name ~params

let check_interpreter ~session ~manifest observation =
  let capability = Extension_manifest.capability manifest in
  let* interpreter =
    Interpreter.make ~name:(Capability.name capability)
      ~version:(Capability.version capability) ()
    |> Result.map_error (fun message ->
           Invalid_result
             {
               operation = Extension_failure.Interpret_observation;
               method_name = "monika.interpretObservation";
               message;
             })
  in
  let method_name = "monika.interpretObservation" in
  let* interpreted =
    call_with_observation session ~method_name
      ~params:(Extension_protocol.interpret_params ~observation)
      observation
    |> runtime ~operation:Extension_failure.Interpret_observation ~method_name
  in
  let* _ =
    Extension_protocol.decode_interpret_result ~manifest
      ~primary_observation:observation interpreted
    |> decode ~operation:Extension_failure.Interpret_observation ~method_name
  in
  let selector = Selector.Whole_observation in
  let method_name = "monika.resolveRegion" in
  let* resolved =
    call_with_observation session ~method_name
      ~params:(Extension_protocol.resolve_params ~observation ~selector)
      observation
    |> runtime ~operation:Extension_failure.Resolve_region ~method_name
  in
  let* _ =
    Extension_protocol.decode_resolve_result ~manifest
      ~target_observation:observation ~requested_selector:selector resolved
    |> decode ~operation:Extension_failure.Resolve_region ~method_name
  in
  let invalid_classification message =
    Invalid_result
      {
        operation = Extension_failure.Classify_region_extents;
        method_name = "monika.classifyRegionExtents";
        message;
      }
  in
  let* full_range =
    Text_range.make ~start:0
      ~end_:
        (Observation.bytes observation |> Option.map String.length
       |> Option.value ~default:0)
    |> Result.map_error invalid_classification
  in
  let* left =
    conformance_region observation interpreter "conformance-left"
      (Selector.Text_range full_range)
    |> Result.map_error invalid_classification
  in
  let* range =
    Text_range.make ~start:0 ~end_:1
    |> Result.map_error invalid_classification
  in
  let* right =
    conformance_region observation interpreter "conformance-right"
      (Selector.Text_range range)
    |> Result.map_error invalid_classification
  in
  let method_name = "monika.classifyRegionExtents" in
  let* params =
    Extension_protocol.classify_region_extents_params ~observation ~left ~right
    |> Result.map_error (fun message ->
           Invalid_result
             {
               operation = Extension_failure.Classify_region_extents;
               method_name;
               message;
             })
  in
  let* classified =
    call_with_observation session ~method_name ~params observation
    |> runtime ~operation:Extension_failure.Classify_region_extents ~method_name
  in
  let* _ =
    Extension_protocol.decode_classify_result classified
    |> decode ~operation:Extension_failure.Classify_region_extents ~method_name
  in
  Ok
    [
      "monika.interpretObservation";
      "monika.resolveRegion";
      "monika.classifyRegionExtents";
    ]

let check_reference_extractor ~session observation =
  let method_name = "monika.extractReferences" in
  let* result =
    call_with_observation session ~method_name
      ~params:
        (Extension_protocol.extract_references_params ~observation
           ~interpretation:None)
      observation
    |> runtime ~operation:Extension_failure.Extract_references ~method_name
  in
  let* _ =
    Extension_protocol.decode_extract_references_result
      ~primary_observation:observation result
    |> decode ~operation:Extension_failure.Extract_references ~method_name
  in
  Ok [ method_name ]

let check_annotation_extractor ~session observation =
  let method_name = "monika.extractAnnotations" in
  let* result =
    call_with_observation session ~method_name
      ~params:
        (Extension_protocol.extract_annotations_params ~observation
           ~interpretation:None)
      observation
    |> runtime ~operation:Extension_failure.Extract_annotations ~method_name
  in
  let* _ =
    Extension_protocol.decode_extract_annotations_result
      ~primary_observation:observation result
    |> decode ~operation:Extension_failure.Extract_annotations ~method_name
  in
  Ok [ method_name ]

let empty_snapshot =
  Workspace_graph_snapshot.make ~observations:[] ~sidecar_snapshots:[]
    ~regions:[] ~annotation_index:(Annotation_index.make [])
    ~reference_index:(Reference_index.make []) ~reference_uses:[] ~relations:[]
    ~reference_edges:[] ~endpoint_resolutions:[] ~diagnostics:[]
    ~coverage:Coverage.empty

let check_auditor ~session =
  let method_name = "monika.audit" in
  let policy = Audit_policy.default in
  let* result =
    Extension_runtime.call session ~method_name
      ~params:
        (Extension_protocol.audit_params ~snapshot:empty_snapshot ~policy)
    |> runtime ~operation:Extension_failure.Audit ~method_name
  in
  let* _ =
    Extension_protocol.decode_audit_result ~policy result
    |> decode ~operation:Extension_failure.Audit ~method_name
  in
  Ok [ method_name ]

let check_deriver ~session =
  let method_name = "monika.derive" in
  let invalid message =
    Invalid_result
      { operation = Extension_failure.Derive; method_name; message }
  in
  let* path =
    Workspace_path.of_canonical_string "docs/conformance.md"
    |> Result.map_error invalid
  in
  let origin = Observation.workspace path in
  let* observation =
    Observation_id.make "observation:docs/conformance.md"
    |> Result.map_error invalid
  in
  let* id =
    Annotation_id.make ~scope:origin ~local:"conformance"
    |> Result.map_error invalid
  in
  let* address =
    Region_address.make ~origin ~selector:Selector.Whole_observation ()
    |> Result.map_error invalid
  in
  let* annotation =
    Annotation.make ~id ~subject:(Region_ref.Address address)
      ~predicate:"conformance" ~object_:(Annotation.Literal "conformance")
    |> Result.map_error invalid
  in
  let* range = Text_range.make ~start:0 ~end_:0 |> Result.map_error invalid in
  let* encoding =
    Observation_encoding.make ~name:"conformance" ~version:"1"
    |> Result.map_error invalid
  in
  let source =
    Source_location.in_observation ~observation
      ~locator:(Source_location.Byte_range range) ~encoding
  in
  let occurrence = Annotation_occurrence.make ~annotation ~source in
  let source_occurrence = Derive_request.Annotation occurrence in
  let request = Derive_request.inline_to_sidecar ~source_occurrence path in
  let conformance_observation =
    Observation.of_bytes ~id:observation ~origin
      ~observation_type:Observation_type.markdown ~bytes:""
  in
  let snapshot =
    Workspace_graph_snapshot.make ~observations:[ conformance_observation ]
      ~sidecar_snapshots:[] ~regions:[]
      ~annotation_index:(Annotation_index.make [ occurrence ])
      ~reference_index:(Reference_index.make []) ~reference_uses:[]
      ~relations:[] ~reference_edges:[] ~endpoint_resolutions:[]
      ~diagnostics:[] ~coverage:Coverage.empty
  in
  let* result =
    Extension_runtime.call session ~method_name
      ~params:
        (Extension_protocol.derive_params ~request ~snapshot)
    |> runtime ~operation:Extension_failure.Derive ~method_name
  in
  let* _ =
    Extension_protocol.decode_derive_result result
    |> decode ~operation:Extension_failure.Derive ~method_name
  in
  Ok [ method_name ]

let check_resource_observer ~session ~manifest =
  let capability = Extension_manifest.capability manifest in
  let method_name = "monika.observeResource" in
  let* observer =
    Resource_observer.make ~name:(Capability.name capability)
      ~version:(Capability.version capability) ()
    |> Result.map_error (fun message ->
           Invalid_result
             {
               operation = Extension_failure.Observe_resource;
               method_name;
               message;
             })
  in
  let* origin =
    Observation.extension ~observer
      ~locator:(`Assoc [ ("conformance", `Bool true) ]) ()
    |> Result.map_error (fun message ->
           Invalid_result
             {
               operation = Extension_failure.Observe_resource;
               method_name;
               message;
             })
  in
  let* result, content =
    Extension_runtime.call_receiving_content session ~method_name
      ~params:(Extension_protocol.observe_resource_params ~origin)
    |> runtime ~operation:Extension_failure.Observe_resource ~method_name
  in
  let* _ =
    Extension_protocol.decode_observe_resource_result ~manifest
      ~requested_origin:origin ~content result
    |> decode ~operation:Extension_failure.Observe_resource ~method_name
  in
  Ok [ method_name ]

let check ~session ~manifest =
  let capability = Extension_manifest.capability manifest in
  match Capability.kind capability with
  | Capability.Interpreter ->
      let* observation =
        conformance_observation capability
        |> Result.map_error (fun message ->
               Invalid_result
                 {
                   operation = Extension_failure.Interpret_observation;
                   method_name = "monika.interpretObservation";
                   message;
                 })
      in
      check_interpreter ~session ~manifest observation
  | Capability.Reference_extractor ->
      let* observation =
        conformance_observation capability
        |> Result.map_error (fun message ->
               Invalid_result
                 {
                   operation = Extension_failure.Extract_references;
                   method_name = "monika.extractReferences";
                   message;
                 })
      in
      check_reference_extractor ~session observation
  | Capability.Annotation_extractor ->
      let* observation =
        conformance_observation capability
        |> Result.map_error (fun message ->
               Invalid_result
                 {
                   operation = Extension_failure.Extract_annotations;
                   method_name = "monika.extractAnnotations";
                   message;
                 })
      in
      check_annotation_extractor ~session observation
  | Capability.Resource_observer ->
      check_resource_observer ~session ~manifest
  | Capability.Auditor -> check_auditor ~session
  | Capability.Deriver -> check_deriver ~session
