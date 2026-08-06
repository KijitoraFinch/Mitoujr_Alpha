type operation = Observe | Resolve_region
type t

val make :
  operation:operation -> code:string -> message:string -> unit -> (t, string) result

val operation : t -> operation
val code : t -> string
val message : t -> string
val compare : t -> t -> int
val equal : t -> t -> bool
