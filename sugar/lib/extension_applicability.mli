type association = Not_associated | Associated of Observation_type.t

(** Validates every path glob without selecting an observation. *)
val validate : Capability.t -> (unit, string) result

(** Determines the observation type assigned by an explicit workspace file
    association. This operation runs before interpretation. Unknown formats
    require a matching path glob and at most one declared ObservationType. *)
val associate :
  Capability.t -> path:Workspace_path.t -> (association, string) result

(** Tests a capability against an already fixed observation. It never creates
    or reclassifies the observation. *)
val accepts :
  Capability.t -> observation:Observation.t -> (bool, string) result
