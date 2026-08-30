type endpoint = Region_ref.t
type t

val make :
  id:Annotation_id.t ->
  subject:endpoint ->
  predicate:string ->
  object_:endpoint ->
  evidence:Annotation_occurrence.t Nonempty.t ->
  (t, string) result

val of_index_entry :
  reference_index:Reference_index.t -> Annotation_index.entry -> t option
val id : t -> Annotation_id.t
val subject : t -> endpoint
val predicate : t -> string
val object_ : t -> endpoint
val evidence : t -> Annotation_occurrence.t Nonempty.t
