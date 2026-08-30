type interpret_result =
  | Interpretation of Interpretation.t
  | Interpret_failure of Extension_failure.t

type extract_references_result =
  | Reference_extraction of Reference_extraction.t
  | Extract_references_failure of Extension_failure.t

type resolve_result =
  | Resolved_region of Region.t
  | Resolve_failure of Extension_failure.t

type classify_result =
  | Classified of Region_extent_relation.t
  | Classify_failure of Extension_failure.t

val interpret_params :
  observation:Observation.t -> Yojson.Safe.t

val extract_references_params :
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

val decode_interpret_result :
  manifest:Extension_manifest.t ->
  primary_observation:Observation.t ->
  Yojson.Safe.t ->
  (interpret_result, string) result

val decode_extract_references_result :
  primary_observation:Observation.t ->
  Yojson.Safe.t ->
  (extract_references_result, string) result

val decode_resolve_result :
  manifest:Extension_manifest.t ->
  target_observation:Observation.t ->
  requested_selector:Selector.t ->
  Yojson.Safe.t ->
  (resolve_result, string) result

val decode_classify_result :
  Yojson.Safe.t -> (classify_result, string) result
