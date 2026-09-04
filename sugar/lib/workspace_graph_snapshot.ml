type t = {
  observations : Observation.t list;
  sidecar_snapshots : Sidecar_snapshot.t list;
  regions : Region.t list;
  annotation_index : Annotation_index.t;
  reference_index : Reference_index.t;
  reference_uses : Reference_use.t list;
  relations : Relation.t list;
  reference_edges : Reference_edge.t list;
  endpoint_resolutions :
    (Region_address.t * Endpoint_resolution.t) list;
  diagnostics : Diagnostic.t list;
  coverage : Coverage.t;
}

let make ~observations ~sidecar_snapshots ~regions ~annotation_index
    ~reference_index ~reference_uses ~relations ~reference_edges
    ~endpoint_resolutions ~diagnostics ~coverage =
  {
    observations;
    sidecar_snapshots;
    regions;
    annotation_index;
    reference_index;
    reference_uses;
    relations;
    reference_edges = List.sort Reference_edge.compare reference_edges;
    endpoint_resolutions =
      List.sort
        (fun (left, _) (right, _) -> Region_address.compare left right)
        endpoint_resolutions;
    diagnostics = List.sort Diagnostic.compare diagnostics;
    coverage;
  }

let observations value = value.observations
let sidecar_snapshots value = value.sidecar_snapshots
let regions value = value.regions
let annotation_index value = value.annotation_index
let reference_index value = value.reference_index
let reference_uses value = value.reference_uses
let relations value = value.relations
let reference_edges value = value.reference_edges
let endpoint_resolutions value = value.endpoint_resolutions
let diagnostics value = value.diagnostics
let coverage value = value.coverage
