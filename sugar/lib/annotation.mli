type object_ =
  | Region_object of Region_ref.t
  | Reference_object of Reference_id.t
  | Literal of string

type t

val make :
  id:Annotation_id.t ->
  subject:Region_ref.t ->
  predicate:string ->
  object_:object_ ->
  (t, string) result

val id : t -> Annotation_id.t
val subject : t -> Region_ref.t
val predicate : t -> string
val object_ : t -> object_
val compare : t -> t -> int
val equal : t -> t -> bool
