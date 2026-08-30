type interpret_result =
  | Interpretation of Interpretation.t
  | Interpret_failure of Extension_failure.t

type observe_result =
  | Observed of Observation.t
  | Observe_failure of Extension_failure.t

type extract_references_result =
  | Reference_extraction of Reference_extraction.t
  | Extract_references_failure of Extension_failure.t

type extract_annotations_result =
  | Annotation_extraction of Annotation_extraction.t
  | Extract_annotations_failure of Extension_failure.t

type resolve_result =
  | Resolved_region of Region.t
  | Resolve_failure of Extension_failure.t

type classify_result =
  | Classified of Region_extent_relation.t
  | Classify_failure of Extension_failure.t

type audit_result =
  | Audit_diagnostics of Diagnostic.t list
  | Audit_failure of Extension_failure.t

type derive_result =
  | Derived_patches of Proposed_patch.t list
  | Derive_failure of Extension_failure.t

val interpret_params :
  observation:Observation.t -> Yojson.Safe.t

val observe_resource_params : origin:Origin.t -> Yojson.Safe.t

val extract_references_params :
  observation:Observation.t ->
  interpretation:Interpretation.t ->
  Yojson.Safe.t

val extract_annotations_params :
  observation:Observation.t ->
  interpretation:Interpretation.t ->
  Yojson.Safe.t

val resolve_params :
  observation:Observation.t ->
  selector:Selector.t ->
  Yojson.Safe.t

val classify_region_extents_params :
  observation:Observation.t ->
  left:Region.t ->
  right:Region.t ->
  (Yojson.Safe.t, string) result

val audit_params :
  snapshot:Workspace_graph_snapshot.t ->
  policy:Audit_policy.t ->
  Yojson.Safe.t

val derive_params :
  request:Derive_request.t ->
  snapshot:Workspace_graph_snapshot.t ->
  Yojson.Safe.t

val decode_interpret_result :
  manifest:Extension_manifest.t ->
  primary_observation:Observation.t ->
  Yojson.Safe.t ->
  (interpret_result, string) result

val decode_observe_resource_result :
  manifest:Extension_manifest.t ->
  requested_origin:Origin.t ->
  content:string option ->
  Yojson.Safe.t ->
  (observe_result, string) result

val decode_extract_references_result :
  primary_observation:Observation.t ->
  Yojson.Safe.t ->
  (extract_references_result, string) result

val decode_extract_annotations_result :
  primary_observation:Observation.t ->
  Yojson.Safe.t ->
  (extract_annotations_result, string) result

val decode_resolve_result :
  manifest:Extension_manifest.t ->
  target_observation:Observation.t ->
  requested_selector:Selector.t ->
  Yojson.Safe.t ->
  (resolve_result, string) result

val decode_classify_result :
  Yojson.Safe.t -> (classify_result, string) result

val decode_audit_result :
  policy:Audit_policy.t ->
  Yojson.Safe.t ->
  (audit_result, string) result

val decode_derive_result :
  Yojson.Safe.t -> (derive_result, string) result
