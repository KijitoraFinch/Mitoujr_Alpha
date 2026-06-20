type t

val of_hex : string -> (t, string) result
val of_content : string -> t
val to_hex : t -> string
val to_string : t -> string
val compare : t -> t -> int
val equal : t -> t -> bool
