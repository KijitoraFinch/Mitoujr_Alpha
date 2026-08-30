let encode value =
  let sidecar_only =
    match Audit_policy.sidecar_only value with
    | Audit_policy.Allow -> "allow"
    | Audit_policy.Report -> "report"
  in
  let severity_overrides =
    Audit_policy.severity_overrides value
    |> List.map (fun (code, severity) ->
           `Assoc
             [
               ("code", `String (Diagnostic.code_string code));
               ("severity", `String (Diagnostic.severity_string severity));
             ])
  in
  `Assoc
    [
      ("sidecarOnly", `String sidecar_only);
      ("severityOverrides", `List severity_overrides);
    ]
