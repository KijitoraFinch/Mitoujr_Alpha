type t

val make : string -> (t, string) result
val to_string : t -> string
val compare : t -> t -> int
val equal : t -> t -> bool
