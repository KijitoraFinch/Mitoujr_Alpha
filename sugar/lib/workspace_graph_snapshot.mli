(** An immutable graph assembled from one stable workspace observation attempt. *)
type t

val make :
  observations:Observation.t list ->
  sidecar_snapshots:Sidecar_snapshot.t list ->
  regions:Region.t list ->
  annotation_index:Annotation_index.t ->
  reference_index:Reference_index.t ->
  reference_uses:Reference_use.t list ->
  relations:Relation.t list ->
  reference_edges:Reference_edge.t list ->
  diagnostics:Diagnostic.t list ->
  coverage:Coverage.t ->
  t

val observations : t -> Observation.t list
val sidecar_snapshots : t -> Sidecar_snapshot.t list
val regions : t -> Region.t list
val annotation_index : t -> Annotation_index.t
val reference_index : t -> Reference_index.t
val reference_uses : t -> Reference_use.t list
val relations : t -> Relation.t list
val reference_edges : t -> Reference_edge.t list
val diagnostics : t -> Diagnostic.t list
val coverage : t -> Coverage.t
