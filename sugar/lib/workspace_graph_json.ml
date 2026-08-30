let list encode values = `List (List.map encode values)
let string value = `String value

let normalized_list normalize encode values =
  values |> List.map normalize |> List.sort Stdlib.compare |> list encode

let endpoint region =
  `Assoc
    [
      ("kind", string "region");
      ( "region",
        region |> Normal.Region_ref.normalize |> Normal_json.region_ref );
    ]

let annotation_index_entry (id, entry) =
  let id =
    id |> Normal.Origin_scoped_id.annotation |> Normal_json.origin_scoped_id
  in
  match entry with
  | Annotation_index.Consistent { value; occurrences } ->
      `Assoc
        [
          ("id", id);
          ("status", string "consistent");
          ("value", value |> Normal.Annotation.normalize |> Normal_json.annotation);
          ( "occurrences",
            occurrences |> Nonempty.to_list
            |> List.sort Annotation_occurrence.compare
            |> list (fun occurrence ->
                   occurrence |> Normal.Annotation_occurrence.normalize
                   |> Normal_json.annotation_occurrence) );
        ]
  | Annotation_index.Conflict { occurrences } ->
      `Assoc
        [
          ("id", id);
          ("status", string "conflict");
          ( "occurrences",
            occurrences |> Nonempty.to_list
            |> List.sort Annotation_occurrence.compare
            |> list (fun occurrence ->
                   occurrence |> Normal.Annotation_occurrence.normalize
                   |> Normal_json.annotation_occurrence) );
        ]

let reference_index_entry (id, entry) =
  let id =
    id |> Normal.Origin_scoped_id.reference |> Normal_json.origin_scoped_id
  in
  match entry with
  | Reference_index.Consistent { value; occurrences } ->
      `Assoc
        [
          ("id", id);
          ("status", string "consistent");
          ("value", value |> Normal.Reference.normalize |> Normal_json.reference);
          ( "occurrences",
            occurrences |> Nonempty.to_list
            |> List.sort Reference_definition_occurrence.compare
            |> list (fun occurrence ->
                   occurrence |> Normal.Reference_definition.normalize
                   |> Normal_json.reference_definition) );
        ]
  | Reference_index.Conflict { occurrences } ->
      `Assoc
        [
          ("id", id);
          ("status", string "conflict");
          ( "occurrences",
            occurrences |> Nonempty.to_list
            |> List.sort Reference_definition_occurrence.compare
            |> list (fun occurrence ->
                   occurrence |> Normal.Reference_definition.normalize
                   |> Normal_json.reference_definition) );
        ]

let relation value =
  `Assoc
    [
      ( "id",
        Relation.id value |> Normal.Origin_scoped_id.annotation
        |> Normal_json.origin_scoped_id );
      ("source", endpoint (Relation.subject value));
      ("predicate", string (Relation.predicate value));
      ("target", endpoint (Relation.object_ value));
      ( "evidence",
        Relation.evidence value |> Nonempty.to_list
        |> List.sort Annotation_occurrence.compare
        |> list (fun occurrence ->
               occurrence |> Normal.Annotation_occurrence.normalize
               |> Normal_json.annotation_occurrence) );
    ]

let resolution = function
  | Endpoint_resolution.Resolved -> "resolved"
  | Endpoint_resolution.Unresolved -> "unresolved"
  | Endpoint_resolution.Invalid_selector -> "invalid-selector"
  | Endpoint_resolution.Unreadable -> "unreadable"
  | Endpoint_resolution.Not_checked -> "not-checked"

let reference_edge_target = function
  | Reference_edge.Address address ->
      `Assoc
        [
          ("kind", string "address");
          ( "address",
            address |> Normal.Region_address.normalize
            |> Normal_json.region_address );
        ]
  | Reference_edge.Unresolved_reference reference ->
      `Assoc
        [
          ("kind", string "unresolved-reference");
          ( "reference",
            reference |> Normal.Origin_scoped_id.reference
            |> Normal_json.origin_scoped_id );
        ]

let reference_edge value =
  `Assoc
    [
      ( "source",
        Reference_edge.source value |> Normal.Region_address.normalize
        |> Normal_json.region_address );
      ("target", reference_edge_target (Reference_edge.target value));
      ( "sourceResolution",
        Reference_edge.source_resolution value |> resolution |> string );
      ( "targetResolution",
        Reference_edge.target_resolution value |> resolution |> string );
      ( "use",
        Reference_edge.use value |> Normal.Reference_use.normalize
        |> Normal_json.reference_use );
    ]

let snapshot value =
  let observations =
    Workspace_graph_snapshot.observations value
    |> normalized_list Normal.Observation.normalize Normal_json.observation
  in
  let sidecar_snapshots =
    Workspace_graph_snapshot.sidecar_snapshots value
    |> normalized_list Normal.Sidecar_snapshot.normalize
         Normal_json.sidecar_snapshot
  in
  let regions =
    Workspace_graph_snapshot.regions value
    |> normalized_list Normal.Region.normalize Normal_json.region
  in
  let annotation_index =
    Workspace_graph_snapshot.annotation_index value
    |> Annotation_index.entries |> list annotation_index_entry
  in
  let reference_index =
    Workspace_graph_snapshot.reference_index value
    |> Reference_index.entries |> list reference_index_entry
  in
  let reference_uses =
    Workspace_graph_snapshot.reference_uses value
    |> List.sort Reference_use.compare
    |> list (fun use ->
           use |> Normal.Reference_use.normalize |> Normal_json.reference_use)
  in
  let relations =
    Workspace_graph_snapshot.relations value |> List.map relation
    |> List.sort Stdlib.compare |> list Fun.id
  in
  let reference_edges =
    Workspace_graph_snapshot.reference_edges value |> List.map reference_edge
    |> List.sort Stdlib.compare |> list Fun.id
  in
  let diagnostics =
    Workspace_graph_snapshot.diagnostics value
    |> List.sort Diagnostic.compare
    |> list (fun diagnostic ->
           diagnostic |> Normal.Diagnostic.normalize |> Normal_json.diagnostic)
  in
  let coverage =
    Workspace_graph_snapshot.coverage value |> Normal.Coverage.normalize
    |> Normal_json.coverage
  in
  `Assoc
    [
      ("schemaVersion", string "2");
      ("observations", observations);
      ("sidecarSnapshots", sidecar_snapshots);
      ("regions", regions);
      ("annotationIndex", annotation_index);
      ("referenceIndex", reference_index);
      ("referenceUses", reference_uses);
      ("relations", relations);
      ("referenceEdges", reference_edges);
      ("diagnostics", diagnostics);
      ("coverage", coverage);
    ]
