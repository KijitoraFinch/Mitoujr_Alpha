type t = Resolved of Region_id.t | Address of Region_address.t

val compare : t -> t -> int
