val check : workspace:string -> Command_result.t

val check_with_registry :
  workspace:string ->
  registry:Registry_snapshot.t ->
  policy:Audit_policy.t ->
  Command_result.t
