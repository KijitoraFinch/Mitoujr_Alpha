type query_direction = Incoming | Outgoing | Both
type edge_direction = Incoming_edge | Outgoing_edge | Internal_edge
type edge_kind = Reference_occurrence | Semantic_relation

type resolution =
  | Resolved
  | Unresolved
  | Invalid_selector
  | Unreadable
  | Not_checked

type edge

type coverage = {
  scanned_observations : int;
  interpreted_observations : int;
  unsupported_observations : int;
  failed_observations : int;
  complete : bool;
}

type t
type error = Usage of string | Internal of string

val query :
  workspace:string ->
  observation:Workspace_path.t ->
  direction:query_direction ->
  predicate:string option ->
  limit:int ->
  (t, error) result

val query_with_extension :
  workspace:string ->
  observation:Workspace_path.t ->
  direction:query_direction ->
  predicate:string option ->
  limit:int ->
  manifest:Extension_manifest.t ->
  executable:string ->
  arguments:string list ->
  (t, error) result

val observation : t -> Workspace_path.t
val query_direction : t -> query_direction
val predicate : t -> string option
val limit : t -> int
val matches : t -> edge list
val coverage : t -> coverage
val truncated : t -> bool

val direction : edge -> edge_direction
val kind : edge -> edge_kind
val edge_predicate : edge -> string
val source : edge -> Region_address.t
val target : edge -> Region_address.t
val reference : edge -> Reference_id.t option
val annotation : edge -> Annotation_id.t option
val occurrence_range : edge -> Text_range.t option
val source_resolution : edge -> resolution
val target_resolution : edge -> resolution
