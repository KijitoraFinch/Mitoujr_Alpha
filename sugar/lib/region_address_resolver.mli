(** Exact resolution of a RegionAddress against one already fixed Observation.
    Partial addresses are dispatched only by their InterpreterIdentity. *)
type t

val resolve :
  registry:Registry_snapshot.t ->
  observation:Observation.t ->
  existing_regions:Region.t list ->
  Region_address.t ->
  (t, string) result

val resolution : t -> Endpoint_resolution.t
val region : t -> Region.t option
val message : t -> string option
val extension_failure : t -> Extension_failure.t option
