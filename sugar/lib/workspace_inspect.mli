type inspection = {
  result : Command_result.t;
  content : string option;
  occurrences : Reference_occurrence.t list;
  relations : Relation.t list;
}

type existing_observation_error =
  | Observation_changed
  | Invalid_observation of string

val inspect_observation :
  workspace:string -> observation:Workspace_path.t -> inspection

val inspect_existing_observation :
  workspace:string ->
  observation:Observation.t ->
  (inspection, existing_observation_error) result

val inspect : workspace:string -> observation:Workspace_path.t -> Command_result.t

val inspect_with_extension :
  workspace:string ->
  observation:Workspace_path.t ->
  manifest:Extension_manifest.t ->
  executable:string ->
  arguments:string list ->
  Command_result.t

val inspect_with_extension_session :
  workspace:string ->
  observation:Workspace_path.t ->
  manifest:Extension_manifest.t ->
  session:Extension_runtime.session ->
  Command_result.t

val inspect_observation_with_extension_session :
  workspace:string ->
  observation:Workspace_path.t ->
  manifest:Extension_manifest.t ->
  session:Extension_runtime.session ->
  inspection

val inspect_existing_observation_with_extension_session :
  workspace:string ->
  observation:Observation.t ->
  manifest:Extension_manifest.t ->
  session:Extension_runtime.session ->
  (inspection, existing_observation_error) result

val inspect_existing_observation_with_installed_extension :
  workspace:string ->
  observation:Observation.t ->
  extension:Installed_extension.t ->
  (inspection, existing_observation_error) result

val inspect_with_registry :
  workspace:string ->
  observation:Workspace_path.t ->
  registry:Registry_snapshot.t ->
  Command_result.t
