type t

val make :
  observation_type:Observation_type.t ->
  key:string ->
  unit ->
  (t, string) result

val of_content :
  observation_type:Observation_type.t -> Content_identity.t -> t

val observation_type : t -> Observation_type.t
val key : t -> string
val compare : t -> t -> int
val equal : t -> t -> bool
