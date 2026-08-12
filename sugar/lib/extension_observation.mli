type observation_result = {
  artifacts : Artifact.t list;
  regions : Region.t list;
  references : Reference.t list;
  annotations : Annotation.t list;
}

type remote_failure = {
  code : string;
  message : string;
  data : Yojson.Safe.t option;
}

type observe_result =
  | Observation of observation_result
  | Failure of remote_failure

type resolve_result =
  | Resolved_region of Region.t
  | Resolve_failure of remote_failure

val observe_params :
  artifact:Artifact.t -> content:string -> Yojson.Safe.t

val resolve_params :
  artifact:Artifact.t ->
  content:string ->
  selector:Selector.t ->
  Yojson.Safe.t

val decode_observe_result :
  descriptor:Extension_descriptor.t ->
  primary_artifact:Artifact.t ->
  Yojson.Safe.t ->
  (observe_result, string) result

val decode_resolve_result :
  descriptor:Extension_descriptor.t ->
  target_artifact:Artifact.t ->
  requested_selector:Selector.t ->
  Yojson.Safe.t ->
  (resolve_result, string) result
