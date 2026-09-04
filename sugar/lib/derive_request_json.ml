let origin value =
  value |> Normal.Origin.normalize |> Normal_json.origin

let source_occurrence = function
  | Derive_request.Annotation occurrence ->
      `Assoc
        [
          ("kind", `String "annotation");
          ( "occurrence",
            occurrence |> Normal.Annotation_occurrence.normalize
            |> Normal_json.annotation_occurrence );
        ]
  | Derive_request.Reference_definition occurrence ->
      `Assoc
        [
          ("kind", `String "reference-definition");
          ( "occurrence",
            occurrence |> Normal.Reference_definition.normalize
            |> Normal_json.reference_definition );
        ]

let encode value =
  `Assoc
    [
      ( "sourceOccurrence",
        source_occurrence (Derive_request.source_occurrence value) );
      ("targetOrigin", origin (Derive_request.target_origin value));
      ("targetEncoding", `String (Derive_request.target_encoding value));
      ("policy", Derive_request.policy value |> Normalized_value.to_yojson);
    ]
