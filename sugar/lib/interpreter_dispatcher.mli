(** Dispatcher for the Interpreter capability. Its selection rules are not
    reused for additive capability kinds such as extractors or auditors. *)
type selected =
  | Built_in_markdown
  | Built_in_jsonl
  | Installed of Installed_extension.t

(** Selects the sole interpreter applicable to an already fixed observation.
    No result means unsupported. More than one applicable interpreter is an
    explicit ambiguity error. *)
val select :
  Registry_snapshot.t -> Observation.t -> (selected option, string) result

(** Resolves an interpreter identity recorded in a Region or RegionAddress.
    This is exact name-and-version dispatch and does not use applicability. *)
val find_exact :
  Registry_snapshot.t -> Interpreter.t -> (selected option, string) result

(** Checks whether an exactly selected interpreter accepts the already fixed
    observation. Exact identity dispatch does not imply applicability. *)
val accepts : selected -> Observation.t -> (bool, string) result

(** Determines a workspace observation type before the observation is fixed.
    Conflicting installed associations are rejected. *)
val classify_path :
  Registry_snapshot.t -> Workspace_path.t -> (Observation_type.t, string) result

val identity : selected -> Interpreter.t
