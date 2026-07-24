type observation = {
  result : Command_result.t;
  content : string option;
  occurrences : Reference_occurrence.t list;
  relations : Relation.t list;
}

val inspect_observation :
  workspace:string -> artifact:Workspace_path.t -> observation

val inspect : workspace:string -> artifact:Workspace_path.t -> Command_result.t
