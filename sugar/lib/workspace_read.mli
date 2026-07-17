type safety_reason =
  | Native_spelling_mismatch
  | Symlink_component
  | Reparse_point
  | Parent_not_directory
  | Target_not_regular_file

type error =
  | Invalid_workspace
  | Missing_artifact
  | Unsafe of safety_reason
  | Unstable_content
  | Filesystem_io of string

type file

val read : workspace:string -> path:Workspace_path.t -> (file, error) result
val content : file -> string
val content_identity : file -> Content_identity.t
