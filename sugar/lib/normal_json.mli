val command_result : Normal.Command_result.t -> Yojson.Safe.t
val command_result_string : Normal.Command_result.t -> string
val observation : Normal.Observation.t -> Yojson.Safe.t
val region : Normal.Region.t -> Yojson.Safe.t
val diagnostic : Normal.Diagnostic.t -> Yojson.Safe.t
val selector : Normal.Selector.t -> Yojson.Safe.t
val patch : Normal.Patch.t -> Yojson.Safe.t
val workspace_snapshot : Normal.Workspace_snapshot.t -> Yojson.Safe.t
