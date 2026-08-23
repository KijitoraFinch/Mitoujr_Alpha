type t

val make :
  observation:Observation.t ->
  regions:Region.t list ->
  references:Reference.t list ->
  annotations:Annotation.t list ->
  (t, string) result

val regions : t -> Region.t list
val references : t -> Reference.t list
val annotations : t -> Annotation.t list
