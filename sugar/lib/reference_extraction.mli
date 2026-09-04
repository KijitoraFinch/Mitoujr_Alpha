(** Explicit Reference definitions and actual Reference uses extracted from one
    fixed primary Observation. *)
type t

val make :
  observation:Observation.t ->
  definitions:Reference_definition_occurrence.t list ->
  uses:Reference_use.t list ->
  (t, string) result

val definitions : t -> Reference_definition_occurrence.t list
val uses : t -> Reference_use.t list
