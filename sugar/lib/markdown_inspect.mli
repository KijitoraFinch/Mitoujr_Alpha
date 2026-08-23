type t = {
  regions : Region.t list;
  references : Reference.t list;
  occurrences : Reference_occurrence.t list;
  annotations : Annotation.t list;
}

val inspect :
  observation:Observation_id.t ->
  path:Workspace_path.t ->
  string ->
  (t, string) result
