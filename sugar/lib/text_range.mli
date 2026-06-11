type t

val make : start:int -> end_:int -> (t, string) result
val start : t -> int
val end_ : t -> int
val length : t -> int
val compare : t -> t -> int
