val suffix : string

val is_metadata : Workspace_path.t -> bool

val for_primary : Workspace_path.t -> (Workspace_path.t, string) result
(** [for_primary path] appends the reserved Sidecar suffix to the complete
    primary filename. It never infers the target from a filename stem; the
    Sidecar's [scope.origin] remains authoritative. *)
