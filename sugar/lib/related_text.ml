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
           (Reference_id.observation reference |> Observation_id.to_string)
           (Reference_id.local reference |> Identifier.to_string)));
  match Workspace_graph.annotation edge with
  | None -> ()
  | Some annotation ->
      Buffer.add_string buffer
        (Printf.sprintf "  annotation: %s#%s\n"
           (Annotation_id.observation annotation |> Observation_id.to_string)
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

let render_diagnostic buffer diagnostic =
  Buffer.add_string buffer
    (Printf.sprintf "- [%s] %s\n"
       (Diagnostic.code diagnostic |> Diagnostic.code_string)
       (Diagnostic.message diagnostic));
  match Diagnostic.extension_failure diagnostic with
  | None -> ()
  | Some failure ->
      Buffer.add_string buffer
        (Printf.sprintf "  extension-operation: %s\n"
           (Extension_failure.operation failure
           |> Extension_failure.operation_string));
      Buffer.add_string buffer
        (Printf.sprintf "  extension-code: %s\n"
           (Extension_failure.code failure));
      (match Extension_failure.data failure with
      | None -> ()
      | Some data ->
          Buffer.add_string buffer
            (Printf.sprintf "  extension-data: %s\n"
               (Yojson.Safe.to_string data)))

let to_string value =
  let buffer = Buffer.create 512 in
  Buffer.add_string buffer
    (Workspace_graph.observation value |> Workspace_path.to_canonical_string);
  (match Workspace_graph.query_region value with
  | None -> ()
  | Some region ->
      Buffer.add_string buffer ("#" ^ Identifier.to_string region);
      Buffer.add_string buffer
        (match Workspace_graph.region_scope value with
        | Some Workspace_graph.Exact -> " (exact)"
        | Some Workspace_graph.Contained -> " (contained)"
        | None -> ""));
  let edges = Workspace_graph.matches value in
  if Workspace_graph.result_status value = Workspace_graph.Failed then
    Buffer.add_string buffer
      "\n\nThe related query failed before a stable graph was produced.\n"
  else if edges = [] then
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
  let diagnostics = Workspace_graph.diagnostics value in
  if diagnostics <> [] then (
    Buffer.add_string buffer "\nDiagnostics\n";
    List.iter (render_diagnostic buffer) diagnostics);
  let coverage = Workspace_graph.coverage value in
  Buffer.add_string buffer
    (Printf.sprintf
       "\nCoverage: %d scanned, %d interpreted, %d unsupported, %d failed; %s\n"
       coverage.scanned_observations coverage.interpreted_observations
       coverage.unsupported_observations coverage.failed_observations
       (if coverage.complete then "complete" else "incomplete"));
  Buffer.contents buffer
