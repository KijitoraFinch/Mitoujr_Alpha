type subject = Region of Region_ref.t

type object_ =
  | Region_object of Region_ref.t
  | Reference_object of Reference_id.t
  | Literal of string

type materialization =
  | Markdown_inline of { artifact : Artifact_id.t; range : Text_range.t }
  | Source_comment of { artifact : Artifact_id.t; range : Text_range.t }
  | Sidecar of { artifact : Artifact_id.t; path : Workspace_path.t option }
  | Generated_index of { artifact : Artifact_id.t }

type t

val make :
  id:Annotation_id.t ->
  subject:subject ->
  predicate:string ->
  object_:object_ ->
  provenance:Provenance.t list ->
  materialization:materialization list ->
  (t, string) result

val id : t -> Annotation_id.t
val subject : t -> subject
val predicate : t -> string
val object_ : t -> object_
val provenance : t -> Provenance.t list
val materialization : t -> materialization list
