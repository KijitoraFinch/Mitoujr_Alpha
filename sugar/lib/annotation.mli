type subject = Region of Identifier.t

type object_ =
  | Region_object of Identifier.t
  | Reference_object of Identifier.t
  | Literal of string

type materialization =
  | Markdown_inline of { artifact : Identifier.t; range : Text_range.t }
  | Source_comment of { artifact : Identifier.t; range : Text_range.t }
  | Sidecar of { artifact : Identifier.t; path : Workspace_path.t option }
  | Generated_index of { artifact : Identifier.t }

type t

val make :
  id:Identifier.t ->
  subject:subject ->
  predicate:string ->
  object_:object_ ->
  provenance:Provenance.t list ->
  materialization:materialization list ->
  (t, string) result

val id : t -> Identifier.t
val subject : t -> subject
val predicate : t -> string
val object_ : t -> object_
val provenance : t -> Provenance.t list
val materialization : t -> materialization list
