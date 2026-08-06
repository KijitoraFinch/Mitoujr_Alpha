type t

val empty : t

val add_patterns :
  base:Workspace_path.t option ->
  string ->
  t ->
  t

val is_ignored :
  t ->
  path:Workspace_path.t ->
  directory:bool ->
  bool
