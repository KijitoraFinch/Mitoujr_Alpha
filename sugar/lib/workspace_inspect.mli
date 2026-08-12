type observation = {
  result : Command_result.t;
  content : string option;
  occurrences : Reference_occurrence.t list;
  relations : Relation.t list;
}

val inspect_observation :
  workspace:string -> artifact:Workspace_path.t -> observation

val inspect : workspace:string -> artifact:Workspace_path.t -> Command_result.t

val inspect_with_extension :
  workspace:string ->
  artifact:Workspace_path.t ->
  descriptor:Extension_descriptor.t ->
  executable:string ->
  arguments:string list ->
  Command_result.t

val inspect_with_extension_session :
  workspace:string ->
  artifact:Workspace_path.t ->
  descriptor:Extension_descriptor.t ->
  session:Extension_runtime.session ->
  Command_result.t
