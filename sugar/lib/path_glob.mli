(** A validated, case-sensitive glob over a complete workspace-relative path.
    A single [*] matches bytes within one path segment. A segment equal to [**]
    matches zero or more complete path segments. *)
type t

val make : string -> (t, string) result
val matches : t -> Workspace_path.t -> bool
