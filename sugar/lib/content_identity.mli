type t

val of_content : string -> t
val make : sha256:string -> byte_length:int -> (t, string) result
val sha256 : t -> string
val byte_length : t -> int
val display_hash : t -> string
val compare : t -> t -> int
val equal : t -> t -> bool
