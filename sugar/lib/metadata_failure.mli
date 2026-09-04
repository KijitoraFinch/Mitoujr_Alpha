type operation = Read | Decode
type t

val make :
  path:Workspace_path.t ->
  ?content_identity:Content_identity.t ->
  operation:operation ->
  code:string ->
  message:string ->
  unit ->
  (t, string) result

val path : t -> Workspace_path.t
val content_identity : t -> Content_identity.t option
val operation : t -> operation
val operation_string : operation -> string
val code : t -> string
val message : t -> string
val to_diagnostic : t -> (Diagnostic.t, string) result
