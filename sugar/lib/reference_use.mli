type source_region = Whole_observation | Region of Region_id.t
type target = Named of Reference_id.t | Direct of Region_address.t
type t

val make :
  source_observation:Observation_id.t ->
  source_region:source_region ->
  source_range:Text_range.t ->
  target:target ->
  (t, string) result

val source_observation : t -> Observation_id.t
val source_region : t -> source_region
val source_range : t -> Text_range.t
val target : t -> target
val compare : t -> t -> int
