type file
type t

val make : (Workspace_path.t * string) list -> (t, string) result
val file_path : file -> Workspace_path.t
val file_content : file -> string
val file_identity : file -> Content_identity.t
val files : t -> file list
val find : Workspace_path.t -> t -> file option
val replace_content : Workspace_path.t -> string -> t -> t
val equal : t -> t -> bool
