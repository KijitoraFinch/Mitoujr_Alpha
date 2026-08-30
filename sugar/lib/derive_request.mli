type t

type source_occurrence =
  | Annotation of Annotation_occurrence.t
  | Reference_definition of Reference_definition_occurrence.t

val make :
  source_occurrence:source_occurrence ->
  target_origin:Origin.t ->
  target_encoding:string ->
  policy:Yojson.Safe.t ->
  unit ->
  (t, string) result

val inline_to_sidecar :
  source_occurrence:source_occurrence -> Workspace_path.t -> t

val source_occurrence : t -> source_occurrence
val target_origin : t -> Origin.t
val target_encoding : t -> string
val policy : t -> Normalized_value.t
val compare : t -> t -> int
