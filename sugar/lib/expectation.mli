type t =
  | Observation_identity of Observation_identity.t
  | Content_identity of Content_identity.t
  | Revision of Revision.t
  | Fingerprint of Fingerprint.t

val compare : t -> t -> int

val matches :
  origin:Origin.t ->
  observation_identity:Observation_identity.t ->
  content_identity:Content_identity.t option ->
  fingerprint:Fingerprint.t option ->
  t ->
  bool
