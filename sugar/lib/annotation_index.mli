type entry =
  | Consistent of {
      value : Annotation.t;
      occurrences : Annotation_occurrence.t Nonempty.t;
    }
  | Conflict of { occurrences : Annotation_occurrence.t Nonempty.t }

type t

val make : Annotation_occurrence.t list -> t
val entries : t -> (Annotation_id.t * entry) list
val find : Annotation_id.t -> t -> entry option
val conflicts : t -> (Annotation_id.t * entry) list
val consistent_values : t -> Annotation.t list
