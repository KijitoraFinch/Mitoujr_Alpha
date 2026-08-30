(** Explicit Reference definitions and actual Reference uses extracted from one
    fixed primary Observation. *)
type t

val make :
  observation:Observation.t ->
  definitions:Reference.t list ->
  uses:Reference_occurrence.t list ->
  (t, string) result

val definitions : t -> Reference.t list
val uses : t -> Reference_occurrence.t list
