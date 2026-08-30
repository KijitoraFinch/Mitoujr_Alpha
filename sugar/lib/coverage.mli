type t

val make :
  primary_resources:int ->
  observed:int ->
  interpreted:int ->
  unsupported:int ->
  failed:int ->
  metadata_discovered:int ->
  metadata_decoded:int ->
  metadata_failed:int ->
  complete:bool ->
  (t, string) result

val empty : t
val primary_resources : t -> int
val observed : t -> int
val interpreted : t -> int
val unsupported : t -> int
val failed : t -> int
val metadata_discovered : t -> int
val metadata_decoded : t -> int
val metadata_failed : t -> int
val complete : t -> bool
val compare : t -> t -> int
val equal : t -> t -> bool
