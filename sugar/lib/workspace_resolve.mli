val canonical_observed_at : string -> (string, string) result

val resolve_address :
  workspace:string ->
  address:Region_address.t ->
  observed_at:string ->
  Command_result.t

val resolve_address_with_extension :
  workspace:string ->
  address:Region_address.t ->
  observed_at:string ->
  manifest:Extension_manifest.t ->
  executable:string ->
  arguments:string list ->
  authority:Extension_authority.t ->
  Command_result.t

val resolve_address_with_registry :
  workspace:string ->
  address:Region_address.t ->
  observed_at:string ->
  registry:Registry_snapshot.t ->
  Command_result.t

val resolve_reference :
  previous_snapshot:Resolution_snapshot.t option ->
  workspace:string ->
  observation:Workspace_path.t ->
  reference:string ->
  observed_at:string ->
  Command_result.t

val resolve_reference_with_extension :
  previous_snapshot:Resolution_snapshot.t option ->
  workspace:string ->
  observation:Workspace_path.t ->
  reference:string ->
  observed_at:string ->
  manifest:Extension_manifest.t ->
  executable:string ->
  arguments:string list ->
  authority:Extension_authority.t ->
  Command_result.t

val resolve_reference_with_registry :
  previous_snapshot:Resolution_snapshot.t option ->
  workspace:string ->
  observation:Workspace_path.t ->
  reference:string ->
  observed_at:string ->
  registry:Registry_snapshot.t ->
  Command_result.t
