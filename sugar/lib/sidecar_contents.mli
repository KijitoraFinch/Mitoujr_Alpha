type t

val make :
  scope:Origin.t ->
  annotations:Annotation_occurrence.t list ->
  reference_definitions:Reference_definition_occurrence.t list ->
  t

val scope : t -> Origin.t
val annotations : t -> Annotation_occurrence.t list
val reference_definitions : t -> Reference_definition_occurrence.t list
