type operation =
  | Session
  | Interpret_observation
  | Extract_annotations
  | Extract_references
  | Observe_resource
  | Audit
  | Derive
  | Resolve_region
  | Classify_region_extents
type t

val make :
  operation:operation ->
  code:string ->
  message:string ->
  ?data:Yojson.Safe.t ->
  unit ->
  (t, string) result

val operation : t -> operation
val operation_string : operation -> string
val code : t -> string
val message : t -> string
val data : t -> Yojson.Safe.t option
val compare : t -> t -> int
val equal : t -> t -> bool
