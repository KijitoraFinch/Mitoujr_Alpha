type t

val make : name:string -> version:string -> (t, string) result
val name : t -> string
val version : t -> string
val compare : t -> t -> int
