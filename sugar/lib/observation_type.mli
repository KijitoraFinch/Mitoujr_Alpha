type t

val make : name:string -> version:string -> unit -> (t, string) result
val binary : t
val name : t -> string
val version : t -> string
val compare : t -> t -> int
val equal : t -> t -> bool
