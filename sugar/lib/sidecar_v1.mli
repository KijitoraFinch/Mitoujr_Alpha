type t = {
  references : Reference.t list;
  annotations : Annotation.t list;
}

val decode :
  primary_artifact:Artifact_id.t ->
  sidecar_artifact:Artifact_id.t ->
  sidecar_path:Workspace_path.t ->
  string ->
  (t, string) result
