type t

val make :
  id:Identifier.t ->
  target:Workspace_path.t ->
  expected_identity:Content_identity.t ->
  resulting_identity:Content_identity.t ->
  edits:Text_edit.t list ->
  reason:string ->
  provenance:Provenance.t ->
  (t, string) result

val id : t -> Identifier.t
val target : t -> Workspace_path.t
val expected_identity : t -> Content_identity.t
val resulting_identity : t -> Content_identity.t
val edits : t -> Text_edit.t list
val reason : t -> string
val provenance : t -> Provenance.t
val compare : t -> t -> int
