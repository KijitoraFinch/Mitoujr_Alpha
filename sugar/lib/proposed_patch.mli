type operation =
  | Create of { content : string }
  | Edit of {
      expected_identity : Content_identity.t;
      edits : Text_edit.t list;
    }

type t

val make :
  id:Patch_id.t ->
  target:Workspace_path.t ->
  expected_identity:Content_identity.t ->
  resulting_identity:Content_identity.t ->
  edits:Text_edit.t list ->
  reason:string ->
  provenance:Provenance.t ->
  (t, string) result

val make_create :
  id:Patch_id.t ->
  target:Workspace_path.t ->
  resulting_identity:Content_identity.t ->
  content:string ->
  reason:string ->
  provenance:Provenance.t ->
  (t, string) result

val id : t -> Patch_id.t
val target : t -> Workspace_path.t
val operation : t -> operation
val expected_identity : t -> Content_identity.t option
val resulting_identity : t -> Content_identity.t
val edits : t -> Text_edit.t list
val create_content : t -> string option
val reason : t -> string
val provenance : t -> Provenance.t
val compare : t -> t -> int
