type section = {
  references : Reference.t list;
  annotations : Annotation.t list;
}

type override_kind = Reference_override | Annotation_override

type override = {
  kind : override_kind;
  local : string;
}

type t = {
  derived : section;
  authored : section;
  references : Reference.t list;
  annotations : Annotation.t list;
  overrides : override list;
}

val decode :
  primary_observation:Observation_id.t ->
  sidecar_observation:Observation_id.t ->
  sidecar_path:Workspace_path.t ->
  string ->
  (t, string) result
