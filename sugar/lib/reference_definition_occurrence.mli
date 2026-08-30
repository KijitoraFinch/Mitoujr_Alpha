type t

val make : reference:Reference.t -> source:Source_location.t -> t
val reference : t -> Reference.t
val source : t -> Source_location.t
val compare : t -> t -> int
