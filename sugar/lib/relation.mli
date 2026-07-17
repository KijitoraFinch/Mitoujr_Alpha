type endpoint = Region of Region_ref.t | Reference of Reference_id.t
type t

val make :
  id:Identifier.t ->
  subject:endpoint ->
  predicate:string ->
  object_:endpoint ->
  (t, string) result

val id : t -> Identifier.t
val subject : t -> endpoint
val predicate : t -> string
val object_ : t -> endpoint
