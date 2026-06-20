type t

val make :
  target:Reference.target ->
  artifact_identity:Content_identity.t ->
  ?region_fingerprint:string ->
  ?display:string ->
  observed_at:string ->
  unit ->
  (t, string) result

val target : t -> Reference.target
val artifact_identity : t -> Content_identity.t
val region_fingerprint : t -> string option
val display : t -> string option
val observed_at : t -> string
val compare : t -> t -> int
