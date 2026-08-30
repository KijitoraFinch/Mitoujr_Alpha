type query_direction = Incoming | Outgoing | Both
type region_scope = Exact | Contained
type edge_direction = Incoming_edge | Outgoing_edge | Internal_edge
type edge_kind = Reference_use | Semantic_relation
type result_status = Complete | Incomplete | Failed

type resolution =
  | Resolved
  | Unresolved
  | Invalid_selector
  | Unreadable
  | Not_checked

type edge_target =
  | Address_target of Region_address.t
  | Unresolved_reference_target of Reference_id.t

type edge

type coverage = Coverage.t

type t
type error = Usage of string | Internal of string

val build_snapshot :
  workspace:string -> (Workspace_graph_snapshot.t, error) result

val build_snapshot_with_registry :
  workspace:string ->
  registry:Registry_snapshot.t ->
  (Workspace_graph_snapshot.t, error) result

val resolve_address :
  Workspace_graph_snapshot.t -> Region_address.t -> Endpoint_resolution.t

val target_observation :
  Workspace_graph_snapshot.t -> Region_address.t -> Observation.t option

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

val query_with_registry :
  workspace:string ->
  observation:Workspace_path.t ->
  direction:query_direction ->
  predicate:string option ->
  limit:int ->
  registry:Registry_snapshot.t ->
  (t, error) result

val query_for_region :
  workspace:string ->
  observation:Workspace_path.t ->
  region:Identifier.t ->
  scope:region_scope ->
  direction:query_direction ->
  predicate:string option ->
  limit:int ->
  (t, error) result

val query_for_region_with_registry :
  workspace:string ->
  observation:Workspace_path.t ->
  region:Identifier.t ->
  scope:region_scope ->
  direction:query_direction ->
  predicate:string option ->
  limit:int ->
  registry:Registry_snapshot.t ->
  (t, error) result

val observation : t -> Workspace_path.t
val query_region : t -> Identifier.t option
val region_scope : t -> region_scope option
val query_direction : t -> query_direction
val predicate : t -> string option
val limit : t -> int
val matches : t -> edge list
val diagnostics : t -> Diagnostic.t list
val result_status : t -> result_status
val coverage : t -> coverage
val truncated : t -> bool

val direction : edge -> edge_direction
val kind : edge -> edge_kind
val edge_predicate : edge -> string
val source : edge -> Region_address.t
val target : edge -> edge_target
val reference : edge -> Reference_id.t option
val annotation : edge -> Annotation_id.t option
val occurrence_range : edge -> Text_range.t option
val source_resolution : edge -> resolution
val target_resolution : edge -> resolution
