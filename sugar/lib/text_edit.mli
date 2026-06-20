type t

val make : range:Text_range.t -> replacement:string -> t
val range : t -> Text_range.t
val replacement : t -> string
val compare : t -> t -> int
