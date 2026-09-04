type t

val make :
  target:Reference.target ->
  observation_identity:Observation_identity.t ->
  ?region_fingerprint:Fingerprint.t ->
  ?display:string ->
  observed_at:string ->
  unit ->
  (t, string) result

val target : t -> Reference.target
val observation_identity : t -> Observation_identity.t
val region_fingerprint : t -> Fingerprint.t option
val display : t -> string option
val observed_at : t -> string

(** Compare only the values that identify the resolved target. Display text and
    observation time are evidence metadata and do not cause tracking drift. *)
val same_resolution : t -> t -> bool
val compare : t -> t -> int
