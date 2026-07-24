type target = Named of Reference_id.t | Direct of Region_address.t
type t

val make :
  source_artifact:Artifact_id.t ->
  ?source_region:Region_id.t ->
  range:Text_range.t ->
  target:target ->
  unit ->
  (t, string) result

val source_artifact : t -> Artifact_id.t
val source_region : t -> Region_id.t option
val range : t -> Text_range.t
val target : t -> target
val compare : t -> t -> int
