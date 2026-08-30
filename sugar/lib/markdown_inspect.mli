type t = {
  regions : Region.t list;
  reference_definitions : Reference_definition_occurrence.t list;
  reference_uses : Reference_use.t list;
  annotation_occurrences : Annotation_occurrence.t list;
}

val inspect :
  observation:Observation.t ->
  string ->
  (t, string) result
