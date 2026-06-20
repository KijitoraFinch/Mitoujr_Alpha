type t

val make : source:string -> ?detail:string -> unit -> (t, string) result
val source : t -> string
val detail : t -> string option
val compare : t -> t -> int
