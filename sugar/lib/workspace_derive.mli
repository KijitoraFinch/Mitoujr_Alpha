val derive_sidecar :
  workspace:string -> observation:Workspace_path.t -> Command_result.t

val derive_with_registry :
  workspace:string ->
  observation:Workspace_path.t ->
  registry:Registry_snapshot.t ->
  deriver_name:string ->
  deriver_version:string ->
  Command_result.t
