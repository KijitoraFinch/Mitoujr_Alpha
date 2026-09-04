(** Returns the media-type-shaped name known by the workspace resource observer
    for a canonical path. Unknown suffixes have no inferred name. *)
val inferred_name : Workspace_path.t -> string option

(** Classifies a workspace file without consulting an interpreter. *)
val classify : Workspace_path.t -> Observation_type.t
