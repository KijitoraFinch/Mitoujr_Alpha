val scan : workspace:string -> Command_result.t

val scan_with_classifier :
  workspace:string ->
  classify:(Workspace_path.t -> (Observation_type.t, string) result) ->
  Command_result.t
