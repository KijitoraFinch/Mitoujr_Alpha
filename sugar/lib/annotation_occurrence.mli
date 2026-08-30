type t

val make : annotation:Annotation.t -> source:Source_location.t -> t
val annotation : t -> Annotation.t
val source : t -> Source_location.t
val compare : t -> t -> int
