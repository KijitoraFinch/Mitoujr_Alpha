let resolution = function
  | Workspace_graph.Resolved -> "resolved"
  | Workspace_graph.Unresolved -> "unresolved"
  | Workspace_graph.Invalid_selector -> "invalid-selector"
  | Workspace_graph.Unreadable -> "unreadable"
  | Workspace_graph.Not_checked -> "not-checked"

let edge_kind = function
  | Workspace_graph.Reference_occurrence -> "reference"
  | Workspace_graph.Semantic_relation -> "relation"

let heading = function
  | Workspace_graph.Outgoing_edge -> "Outgoing"
  | Workspace_graph.Incoming_edge -> "Incoming"
  | Workspace_graph.Internal_edge -> "Internal"

let render_edge buffer edge =
  Buffer.add_string buffer
    (Printf.sprintf "- [%s] %s --%s--> %s [%s]\n"
       (edge_kind (Workspace_graph.kind edge))
       (Agent_format.address (Workspace_graph.source edge))
       (Workspace_graph.edge_predicate edge)
       (Agent_format.address (Workspace_graph.target edge))
       (resolution (Workspace_graph.target_resolution edge)));
  if Workspace_graph.source_resolution edge <> Workspace_graph.Resolved then
    Buffer.add_string buffer
      (Printf.sprintf "  source-state: %s\n"
         (resolution (Workspace_graph.source_resolution edge)));
  (match Workspace_graph.reference edge with
  | None -> ()
  | Some reference ->
      Buffer.add_string buffer
        (Printf.sprintf "  reference: %s#%s\n"
           (Reference_id.artifact reference |> Artifact_id.to_string)
           (Reference_id.local reference |> Identifier.to_string)));
  match Workspace_graph.annotation edge with
  | None -> ()
  | Some annotation ->
      Buffer.add_string buffer
        (Printf.sprintf "  annotation: %s#%s\n"
           (Annotation_id.artifact annotation |> Artifact_id.to_string)
           (Annotation_id.local annotation |> Identifier.to_string))

let render_section buffer direction edges =
  let selected =
    List.filter
      (fun edge -> Workspace_graph.direction edge = direction)
      edges
  in
  match selected with
  | [] -> ()
  | _ ->
      Buffer.add_string buffer ("\n" ^ heading direction ^ "\n");
      List.iter (render_edge buffer) selected

let to_string value =
  let buffer = Buffer.create 512 in
  Buffer.add_string buffer
    (Workspace_graph.artifact value |> Workspace_path.to_canonical_string);
  let edges = Workspace_graph.matches value in
  if edges = [] then
    Buffer.add_string buffer
      "\n\nNo explicit relation was observed within the coverage below.\n"
  else (
    render_section buffer Workspace_graph.Outgoing_edge edges;
    render_section buffer Workspace_graph.Incoming_edge edges;
    render_section buffer Workspace_graph.Internal_edge edges);
  if Workspace_graph.truncated value then
    Buffer.add_string buffer
      (Printf.sprintf "\nResults truncated at %d matches.\n"
         (Workspace_graph.limit value));
  let coverage = Workspace_graph.coverage value in
  Buffer.add_string buffer
    (Printf.sprintf
       "\nCoverage: %d scanned, %d interpreted, %d unsupported, %d failed; %s\n"
       coverage.scanned_artifacts coverage.interpreted_artifacts
       coverage.unsupported_artifacts coverage.failed_artifacts
       (if coverage.complete then "complete" else "incomplete"));
  Buffer.contents buffer
