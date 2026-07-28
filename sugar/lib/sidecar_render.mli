val derived_section :
  primary_path:Workspace_path.t ->
  references:Reference.t list ->
  annotations:Annotation.t list ->
  (string, string) result

val new_document :
  primary_path:Workspace_path.t ->
  references:Reference.t list ->
  annotations:Annotation.t list ->
  (string, string) result
