type source_selector =
  | Annotation of Identifier.t
  | Reference_definition of Identifier.t

val derive_sidecar :
  workspace:string ->
  observation:Workspace_path.t ->
  source:source_selector ->
  Command_result.t

val derive_with_registry :
  workspace:string ->
  observation:Workspace_path.t ->
  source:source_selector ->
  registry:Registry_snapshot.t ->
  deriver_name:string ->
  deriver_version:string ->
  Command_result.t
