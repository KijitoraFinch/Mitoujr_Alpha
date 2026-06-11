type origin =
  | Workspace of Workspace_path.t
  | Git of { repo : string; rev : string option; path : string }
  | Web of string
  | Generated of string
  | External of string

type t

val make :
  id:Identifier.t ->
  origin:origin ->
  ?media_type:string ->
  content_identity:Content_identity.t ->
  unit ->
  t

val id : t -> Identifier.t
val origin : t -> origin
val media_type : t -> string option
val content_identity : t -> Content_identity.t
val compare_origin : origin -> origin -> int
