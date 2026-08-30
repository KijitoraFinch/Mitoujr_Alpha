let origin value =
  value |> Normal.Origin.normalize |> Normal_json.origin

let encode value =
  `Assoc
    [
      ("sourceOrigin", origin (Derive_request.source_origin value));
      ("targetOrigin", origin (Derive_request.target_origin value));
      ("targetEncoding", `String (Derive_request.target_encoding value));
      ("policy", Derive_request.policy value |> Normalized_value.to_yojson);
    ]
