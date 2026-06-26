let assoc fields = `Assoc fields
let string value = `String value
let int value = `Int value
let list encode values = `List (List.map encode values)

let add_optional name encode value fields =
  match value with
  | None -> fields
  | Some value -> (name, encode value) :: fields

let content_identity (value : Normal.Content_identity.t) =
  assoc [ ("hash", string value.hash); ("size", int value.size) ]

let range (value : Normal.Range.t) =
  assoc [ ("start", int value.start); ("end", int value.end_) ]

let selector_literal = function
  | Normal.Selector.String value -> string value
  | Normal.Selector.Int value -> int value
  | Normal.Selector.Bool value -> `Bool value

let selector = function
  | Normal.Selector.Whole_artifact ->
      assoc [ ("kind", string "whole-artifact") ]
  | Normal.Selector.Region_id id ->
      assoc [ ("kind", string "region-id"); ("id", string id) ]
  | Normal.Selector.Text_range value ->
      assoc [ ("kind", string "text-range"); ("range", range value) ]
  | Normal.Selector.Row_filter value ->
      assoc
        [
          ("kind", string "row-filter");
          ( "where",
            assoc
              (List.map
                 (fun (name, condition) ->
                   (name, selector_literal condition))
                 value.where) );
        ]

let origin = function
  | Normal.Origin.Workspace path ->
      assoc [ ("kind", string "workspace"); ("path", string path) ]
  | Normal.Origin.Git value ->
      [
        ("kind", string "git");
        ("repo", string value.repo);
        ("path", string value.path);
      ]
      |> add_optional "rev" string value.rev
      |> List.rev |> assoc
  | Normal.Origin.Web url ->
      assoc [ ("kind", string "web"); ("url", string url) ]
  | Normal.Origin.Generated name ->
      assoc [ ("kind", string "generated"); ("name", string name) ]
  | Normal.Origin.External uri ->
      assoc [ ("kind", string "external"); ("uri", string uri) ]

let provenance (value : Normal.Provenance.t) =
  [ ("source", string value.source) ]
  |> add_optional "detail" string value.detail
  |> List.rev |> assoc

let edit (value : Normal.Patch.edit) =
  assoc
    [
      ("range", range value.range);
      ("replacement", string value.replacement);
    ]

let patch (value : Normal.Patch.t) =
  assoc
    [
      ("id", string value.id);
      ("target", string value.target);
      ("expectedContentIdentity", content_identity value.expected_identity);
      ("resultingContentIdentity", content_identity value.resulting_identity);
      ("edits", list edit value.edits);
      ("reason", string value.reason);
      ("provenance", provenance value.provenance);
    ]

let snapshot_target (value : Normal.Snapshot.target) =
  [ ("artifact", origin value.artifact) ]
  |> add_optional "selector" selector value.selector
  |> add_optional "interpreter" string value.interpreter
  |> List.rev |> assoc

let snapshot (value : Normal.Snapshot.t) =
  [
    ("target", snapshot_target value.target);
    ("artifactIdentity", content_identity value.artifact_identity);
    ("observedAt", string value.observed_at);
  ]
  |> add_optional "regionFingerprint" string value.region_fingerprint
  |> add_optional "display" string value.display
  |> List.rev |> assoc

let location (value : Normal.Diagnostic.location) =
  []
  |> add_optional "artifact" string value.artifact
  |> add_optional "region" string value.region
  |> add_optional "annotation" string value.annotation
  |> add_optional "range" range value.range
  |> List.rev |> assoc

let diagnostic (value : Normal.Diagnostic.t) =
  [
    ("code", string value.code);
    ("defaultSeverity", string value.default_severity);
    ("effectiveSeverity", string value.effective_severity);
    ("message", string value.message);
    ("suggestedFixes", list patch value.suggested_fixes);
  ]
  |> add_optional "location" location value.location
  |> List.rev |> assoc

let conflict (value : Normal.Conflict.t) =
  let common kind =
    [
      ("kind", string kind);
      ("patchId", string value.patch_id);
      ("target", string value.target);
    ]
  in
  match value.detail with
  | Normal.Conflict.Missing_artifact -> assoc (common "missing-artifact")
  | Normal.Conflict.Identity_mismatch detail ->
      assoc
        (common "identity-mismatch"
        @ [
            ("expected", content_identity detail.expected);
            ("actual", content_identity detail.actual);
          ])
  | Normal.Conflict.Result_identity_mismatch detail ->
      assoc
        (common "result-identity-mismatch"
        @ [
            ("declared", content_identity detail.declared);
            ("actual", content_identity detail.actual);
          ])
  | Normal.Conflict.Range_out_of_bounds detail ->
      assoc
        (common "range-out-of-bounds"
        @ [
            ("range", range detail.range);
            ("contentLength", int detail.content_length);
          ])
  | Normal.Conflict.Overlapping_edits detail ->
      assoc
        (common "overlapping-edits"
        @ [ ("left", range detail.left); ("right", range detail.right) ])
  | Normal.Conflict.Filesystem_safety detail ->
      assoc
        (common "filesystem-safety"
        @ [ ("reason", string detail.reason) ])

let changed_artifact (value : Normal.Command_result.changed_artifact) =
  assoc
    [
      ("path", string value.path);
      ("before", content_identity value.before);
      ("after", content_identity value.after);
    ]

let workspace_file (value : Normal.Workspace_snapshot.file) =
  assoc
    [
      ("path", string value.path);
      ("contentHex", string value.content_hex);
      ("contentIdentity", content_identity value.content_identity);
    ]

let workspace_snapshot (value : Normal.Workspace_snapshot.t) =
  assoc [ ("files", list workspace_file value.files) ]

let summary_value = function
  | Command_result.Count value -> int value
  | Command_result.Text value -> string value
  | Command_result.Flag value -> `Bool value

let command_result (value : Normal.Command_result.t) =
  [
    ("schemaVersion", string value.schema_version);
    ("command", string value.command);
    ("status", string value.status);
    ("diagnostics", list diagnostic value.diagnostics);
    ("patches", list patch value.patches);
    ("changedArtifacts", list changed_artifact value.changed_artifacts);
    ("conflicts", list conflict value.conflicts);
    ("snapshots", list snapshot value.snapshots);
    ("exitClass", string value.exit_class);
  ]
  |> add_optional "summary"
       (fun values ->
         assoc
           (List.map
              (fun (name, value) -> (name, summary_value value))
              values))
       value.summary
  |> List.rev |> assoc

let command_result_string value =
  command_result value |> Yojson.Safe.to_string
