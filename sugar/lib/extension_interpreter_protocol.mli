type remote_failure = {
  code : string;
  message : string;
  data : Yojson.Safe.t option;
}

type interpret_result =
  | Interpretation of Interpretation.t
  | Interpret_failure of remote_failure

type resolve_result =
  | Resolved_region of Region.t
  | Resolve_failure of remote_failure

val interpret_params :
  observation:Observation.t -> content:string -> Yojson.Safe.t

val resolve_params :
  observation:Observation.t ->
  content:string ->
  selector:Selector.t ->
  Yojson.Safe.t

val decode_interpret_result :
  manifest:Extension_manifest.t ->
  primary_observation:Observation.t ->
  Yojson.Safe.t ->
  (interpret_result, string) result

val decode_resolve_result :
  manifest:Extension_manifest.t ->
  target_observation:Observation.t ->
  requested_selector:Selector.t ->
  Yojson.Safe.t ->
  (resolve_result, string) result
