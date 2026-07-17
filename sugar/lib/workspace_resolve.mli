val canonical_observed_at : string -> (string, string) result

val resolve_reference :
  workspace:string ->
  artifact:Workspace_path.t ->
  reference:string ->
  observed_at:string ->
  Command_result.t
