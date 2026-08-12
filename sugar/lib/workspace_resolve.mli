val canonical_observed_at : string -> (string, string) result

val resolve_reference :
  workspace:string ->
  artifact:Workspace_path.t ->
  reference:string ->
  observed_at:string ->
  Command_result.t

val resolve_reference_with_extension :
  workspace:string ->
  artifact:Workspace_path.t ->
  reference:string ->
  observed_at:string ->
  descriptor:Extension_descriptor.t ->
  executable:string ->
  arguments:string list ->
  Command_result.t
