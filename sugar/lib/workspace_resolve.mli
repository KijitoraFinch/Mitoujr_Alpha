val canonical_observed_at : string -> (string, string) result

val resolve_reference :
  workspace:string ->
  observation:Workspace_path.t ->
  reference:string ->
  observed_at:string ->
  Command_result.t

val resolve_reference_with_extension :
  workspace:string ->
  observation:Workspace_path.t ->
  reference:string ->
  observed_at:string ->
  manifest:Extension_manifest.t ->
  executable:string ->
  arguments:string list ->
  Command_result.t

val resolve_reference_with_registry :
  workspace:string ->
  observation:Workspace_path.t ->
  reference:string ->
  observed_at:string ->
  registry:Registry_snapshot.t ->
  Command_result.t
