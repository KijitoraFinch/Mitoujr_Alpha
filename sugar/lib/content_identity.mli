type t

val of_content : string -> t
val of_sha256_hex : sha256_hex:string -> byte_length:int -> (t, string) result
val of_display_hash : hash:string -> byte_length:int -> (t, string) result
val sha256_hex : t -> string
val byte_length : t -> int
val display_hash : t -> string
val compare : t -> t -> int
val equal : t -> t -> bool
