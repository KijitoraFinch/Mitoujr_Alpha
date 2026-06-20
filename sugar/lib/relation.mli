type endpoint = Region of Identifier.t | Reference of Identifier.t
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
