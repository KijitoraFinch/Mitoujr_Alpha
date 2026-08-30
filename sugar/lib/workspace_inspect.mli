type inspection = {
  result : Command_result.t;
  content : string option;
  interpretation : Interpretation.t option;
  reference_uses : Reference_use.t list;
  reference_index : Reference_index.t;
  annotation_index : Annotation_index.t;
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

val inspect_fixed_observation :
  observation:Observation.t ->
  sidecar_snapshots:Sidecar_snapshot.t list ->
  base_diagnostics:Diagnostic.t list ->
  (inspection, existing_observation_error) result

val inspect : workspace:string -> observation:Workspace_path.t -> Command_result.t

val inspect_with_extension :
  workspace:string ->
  observation:Workspace_path.t ->
  manifest:Extension_manifest.t ->
  executable:string ->
  arguments:string list ->
  authority:Extension_authority.t ->
  Command_result.t

val inspect_observation_with_extension :
  workspace:string ->
  observation:Workspace_path.t ->
  manifest:Extension_manifest.t ->
  executable:string ->
  arguments:string list ->
  authority:Extension_authority.t ->
  inspection

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

val inspect_existing_observation_with_registry :
  workspace:string ->
  observation:Observation.t ->
  registry:Registry_snapshot.t ->
  (inspection, existing_observation_error) result

val inspect_fixed_observation_with_registry :
  observation:Observation.t ->
  sidecar_snapshots:Sidecar_snapshot.t list ->
  base_diagnostics:Diagnostic.t list ->
  registry:Registry_snapshot.t ->
  (inspection, existing_observation_error) result

val inspect_with_registry :
  workspace:string ->
  observation:Workspace_path.t ->
  registry:Registry_snapshot.t ->
  Command_result.t

val inspect_observation_with_registry :
  workspace:string ->
  observation:Workspace_path.t ->
  registry:Registry_snapshot.t ->
  inspection
