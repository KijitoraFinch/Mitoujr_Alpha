type t

val make :
  observation:Observation.t ->
  occurrences:Annotation_occurrence.t list ->
  (t, string) result

val occurrences : t -> Annotation_occurrence.t list
