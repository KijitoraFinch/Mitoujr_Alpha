type applied = {
  snapshot : Workspace_snapshot.t;
  changed : Command_result.changed_file;
}

type result =
  | Applied of applied
  | No_change of Workspace_snapshot.t
  | Conflict of Conflict.t
  | Internal_error of string

val apply_patch : Workspace_snapshot.t -> Proposed_patch.t -> result
