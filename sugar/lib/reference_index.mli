type entry =
  | Consistent of {
      value : Reference.t;
      occurrences : Reference_definition_occurrence.t Nonempty.t;
    }
  | Conflict of { occurrences : Reference_definition_occurrence.t Nonempty.t }

type t

val make : Reference_definition_occurrence.t list -> t
val entries : t -> (Reference_id.t * entry) list
val find : Reference_id.t -> t -> entry option
val conflicts : t -> (Reference_id.t * entry) list
val consistent_values : t -> Reference.t list
