type t

val of_bytes : path:Workspace_path.t -> string -> t

val make :
  path:Workspace_path.t ->
  content_identity:Content_identity.t ->
  bytes:string ->
  (t, string) result

val path : t -> Workspace_path.t
val content_identity : t -> Content_identity.t
val bytes : t -> string
val compare : t -> t -> int
