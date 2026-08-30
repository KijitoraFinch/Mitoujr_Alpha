type endpoint = Region of Region_ref.t | Reference of Reference_id.t
type t

val make :
  id:Annotation_id.t ->
  subject:endpoint ->
  predicate:string ->
  object_:endpoint ->
  evidence:Annotation_occurrence.t Nonempty.t ->
  (t, string) result

val of_index_entry : Annotation_index.entry -> t option
val id : t -> Annotation_id.t
val subject : t -> endpoint
val predicate : t -> string
val object_ : t -> endpoint
val evidence : t -> Annotation_occurrence.t Nonempty.t
