(** Classifies two extents in one fixed Observation. Whole-observation cases
    are decided by core. Partial regions are sent only to their exact
    Interpreter implementation. *)
val classify :
  registry:Registry_snapshot.t ->
  observation:Observation.t ->
  left:Region.t ->
  right:Region.t ->
  (Region_extent_relation.t, Extension_failure.t) result
