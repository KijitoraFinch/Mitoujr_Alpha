type target =
  | Address of Region_address.t
  | Unresolved_reference of Reference_id.t

type t

val make :
  source:Region_address.t ->
  target:target ->
  source_resolution:Endpoint_resolution.t ->
  target_resolution:Endpoint_resolution.t ->
  use:Reference_use.t ->
  t

val source : t -> Region_address.t
val target : t -> target
val source_resolution : t -> Endpoint_resolution.t
val target_resolution : t -> Endpoint_resolution.t
val use : t -> Reference_use.t
val compare : t -> t -> int
