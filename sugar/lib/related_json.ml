let string value = `String value
let int value = `Int value
let bool value = `Bool value
let object_ members = `Assoc members

let range value =
  object_
    [
      ("start", int (Text_range.start value));
      ("end", int (Text_range.end_ value));
    ]

let selector_literal = function
  | Selector.Literal.String value -> string value
  | Selector.Literal.Int value -> int value
  | Selector.Literal.Bool value -> bool value

let selector = function
  | Selector.Whole_artifact -> object_ [ ("kind", string "whole-artifact") ]
  | Selector.Region_id id ->
      object_
        [
          ("kind", string "region-id");
          ("id", string (Identifier.to_string id));
        ]
  | Selector.Text_range value ->
      object_
        [ ("kind", string "text-range"); ("range", range value) ]
  | Selector.Row_filter filter ->
      let where =
        Selector.Row_filter.conditions filter
        |> List.map (fun (field, literal) ->
               ( Selector.Field_name.to_string field,
                 selector_literal literal ))
      in
      object_
        [
          ("kind", string "row-filter");
          ("where", object_ where);
        ]
  | Selector.Extension extension ->
      object_
        [
          ("kind", string "extension");
          ("schema", string (Selector.Extension.schema extension));
          ("value", Selector.Extension.value extension);
        ]

let origin = function
  | Origin.Workspace path ->
      object_
        [
          ("kind", string "workspace");
          ("path", string (Workspace_path.to_canonical_string path));
        ]
  | Origin.Git value ->
      object_
        ([
           ("kind", string "git");
           ("repo", string value.repo);
           ("path", string value.path);
         ]
        @
        match value.rev with None -> [] | Some rev -> [ ("rev", string rev) ])
  | Origin.Web url ->
      object_ [ ("kind", string "web"); ("url", string url) ]
  | Origin.Generated name ->
      object_ [ ("kind", string "generated"); ("name", string name) ]
  | Origin.External uri ->
      object_ [ ("kind", string "external"); ("uri", string uri) ]
  | Origin.Extension value ->
      object_
        [
          ("kind", string "extension");
          ("provider", string value.provider);
          ("locator", string value.locator);
        ]

let address value =
  object_
    ([
       ("artifact", origin (Region_address.artifact value));
       ("selector", selector (Region_address.selector value));
     ]
    @
    match Region_address.interpreter value with
    | None -> []
    | Some interpreter ->
        [
          ("interpreter", string interpreter);
          ( "interpreterVersion",
            string (Region_address.interpreter_version value |> Option.get) );
        ])

let scoped_id artifact local =
  object_
    [
      ("artifact", string (Artifact_id.to_string artifact));
      ("local", string (Identifier.to_string local));
    ]

let reference_id value =
  scoped_id (Reference_id.artifact value) (Reference_id.local value)

let annotation_id value =
  scoped_id (Annotation_id.artifact value) (Annotation_id.local value)

let query_direction = function
  | Workspace_graph.Incoming -> "incoming"
  | Workspace_graph.Outgoing -> "outgoing"
  | Workspace_graph.Both -> "both"

let edge_direction = function
  | Workspace_graph.Incoming_edge -> "incoming"
  | Workspace_graph.Outgoing_edge -> "outgoing"
  | Workspace_graph.Internal_edge -> "internal"

let edge_kind = function
  | Workspace_graph.Reference_occurrence -> "reference-occurrence"
  | Workspace_graph.Semantic_relation -> "semantic-relation"

let resolution = function
  | Workspace_graph.Resolved -> "resolved"
  | Workspace_graph.Unresolved -> "unresolved"
  | Workspace_graph.Invalid_selector -> "invalid-selector"
  | Workspace_graph.Unreadable -> "unreadable"
  | Workspace_graph.Not_checked -> "not-checked"

let evidence edge =
  let members =
    []
    |> (fun values ->
         match Workspace_graph.reference edge with
         | None -> values
         | Some reference ->
             ("reference", reference_id reference) :: values)
    |> (fun values ->
         match Workspace_graph.annotation edge with
         | None -> values
         | Some annotation ->
             ("annotation", annotation_id annotation) :: values)
    |> (fun values ->
         match Workspace_graph.occurrence_range edge with
         | None -> values
         | Some value -> ("range", range value) :: values)
    |> List.rev
  in
  match members with [] -> [] | _ -> [ ("evidence", object_ members) ]

let edge value =
  object_
    ([
       ("direction", string (edge_direction (Workspace_graph.direction value)));
       ("kind", string (edge_kind (Workspace_graph.kind value)));
       ("predicate", string (Workspace_graph.edge_predicate value));
       ("source", address (Workspace_graph.source value));
       ("target", address (Workspace_graph.target value));
       ( "sourceResolution",
         string (resolution (Workspace_graph.source_resolution value)) );
       ( "targetResolution",
         string (resolution (Workspace_graph.target_resolution value)) );
     ]
    @ evidence value)

let coverage value =
  object_
    [
      ("scannedArtifacts", int value.Workspace_graph.scanned_artifacts);
      ("interpretedArtifacts", int value.interpreted_artifacts);
      ("unsupportedArtifacts", int value.unsupported_artifacts);
      ("failedArtifacts", int value.failed_artifacts);
      ("complete", bool value.complete);
    ]

let to_yojson value =
  let query =
    object_
      ([
         ( "artifact",
           string
             (Workspace_graph.artifact value
             |> Workspace_path.to_canonical_string) );
         ( "direction",
           string
             (Workspace_graph.query_direction value |> query_direction) );
         ("limit", int (Workspace_graph.limit value));
       ]
      @
      match Workspace_graph.predicate value with
      | None -> []
      | Some predicate -> [ ("predicate", string predicate) ])
  in
  object_
    [
      ("schemaVersion", string "2");
      ("query", query);
      ( "matches",
        `List (List.map edge (Workspace_graph.matches value)) );
      ("coverage", coverage (Workspace_graph.coverage value));
      ("truncated", bool (Workspace_graph.truncated value));
    ]

let to_string value = Yojson.Safe.pretty_to_string (to_yojson value) ^ "\n"
