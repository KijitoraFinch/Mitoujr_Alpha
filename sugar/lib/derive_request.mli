type t

val make :
  source_origin:Origin.t ->
  target_origin:Origin.t ->
  target_encoding:string ->
  policy:Yojson.Safe.t ->
  unit ->
  (t, string) result

val inline_to_sidecar : Workspace_path.t -> t
val source_origin : t -> Origin.t
val target_origin : t -> Origin.t
val target_encoding : t -> string
val policy : t -> Normalized_value.t
val compare : t -> t -> int
