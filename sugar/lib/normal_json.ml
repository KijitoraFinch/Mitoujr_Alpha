let assoc fields = `Assoc fields
let string value = `String value
let int value = `Int value
let list encode values = `List (List.map encode values)

let add_optional name encode value fields =
  match value with
  | None -> fields
  | Some value -> (name, encode value) :: fields

let add_interpreter (value : Normal.Interpreter_identity.t option) fields =
  match value with
  | None -> fields
  | Some value ->
      ("interpreterVersion", string value.version)
      :: ("interpreter", string value.name)
      :: fields

let content_identity (value : Normal.Content_identity.t) =
  assoc [ ("hash", string value.hash); ("size", int value.size) ]

let range (value : Normal.Range.t) =
  assoc [ ("start", int value.start); ("end", int value.end_) ]

let selector_literal = function
  | Normal.Selector.String value -> string value
  | Normal.Selector.Int value -> int value
  | Normal.Selector.Bool value -> `Bool value

let selector = function
  | Normal.Selector.Whole_observation ->
      assoc [ ("kind", string "whole-observation") ]
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
  | Normal.Selector.Extension extension ->
      assoc
        [
          ("kind", string "extension");
          ("schema", string extension.schema);
          ("value", extension.value);
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
  | Normal.Origin.Extension value ->
      assoc
        [
          ("kind", string "extension");
          ( "observer",
            assoc
              [
                ("name", string value.observer.name);
                ("version", string value.observer.version);
              ] );
          ("locator", value.locator);
        ]

let provenance (value : Normal.Provenance.t) =
  [ ("source", string value.source) ]
  |> add_optional "detail" string value.detail
  |> List.rev |> assoc

let observation_type (value : Normal.Observation_type.t) =
  assoc
    [
      ("name", string value.name);
      ("version", string value.version);
    ]

let observation_identity (value : Normal.Observation_identity.t) =
  assoc
    [
      ("observationType", observation_type value.observation_type);
      ("key", string value.key);
    ]

let observation_representation = function
  | Normal.Observation.Bytes -> assoc [ ("kind", string "bytes") ]
  | Normal.Observation.Structured value ->
      assoc
        [
          ("kind", string "structured");
          ("schema", string value.schema);
          ("value", value.value);
        ]

let observation (value : Normal.Observation.t) =
  [
    ("id", string value.id);
    ("origin", origin value.origin);
    ("identity", observation_identity value.identity);
    ("representation", observation_representation value.representation);
  ]
  |> add_optional "contentIdentity" content_identity value.content_identity
  |> List.rev |> assoc

let observation_scoped_id (value : Normal.Scoped_id.t) =
  assoc [ ("observation", string value.observation); ("local", string value.local) ]

let region_address (value : Normal.Region_address.t) =
  [ ("origin", origin value.origin); ("selector", selector value.selector) ]
  |> add_interpreter value.interpreter
  |> List.rev |> assoc

let region_ref = function
  | Normal.Region_ref.Resolved id ->
      assoc
        [
          ("kind", string "resolved");
          ("id", observation_scoped_id id);
        ]
  | Normal.Region_ref.Address address ->
      assoc
        [
          ("kind", string "address");
          ("address", region_address address);
        ]

let region (value : Normal.Region.t) =
  ([
     ("id", observation_scoped_id value.id);
     ("selector", selector value.selector);
   ]
  @
  match value.interpreter with
  | None -> []
  | Some interpreter ->
      [
        ("interpreterVersion", string interpreter.version);
        ("interpreter", string interpreter.name);
      ]
  )
  |> add_optional "summary" string value.summary
  |> add_optional "range" range value.range
  |> add_optional "fingerprint" string value.fingerprint
  |> List.rev |> assoc

let expectation = function
  | Normal.Expectation.Digest digest ->
      assoc [ ("kind", string "digest"); ("digest", string digest) ]

let reference (value : Normal.Reference.t) =
  assoc
    [
      ("id", observation_scoped_id value.id);
      ("target", region_address value.target);
      ("binding", string value.binding);
      ("expectations", list expectation value.expectations);
      ("provenance", list provenance value.provenance);
    ]

let annotation_object = function
  | Normal.Annotation.Region_object region ->
      assoc [ ("kind", string "region"); ("region", region_ref region) ]
  | Normal.Annotation.Reference_object reference ->
      assoc
        [
          ("kind", string "reference");
          ("reference", observation_scoped_id reference);
        ]
  | Normal.Annotation.Literal value ->
      assoc [ ("kind", string "literal"); ("value", string value) ]

let materialization = function
  | Normal.Annotation.Markdown_inline value ->
      assoc
        [
          ("kind", string "markdown-inline");
          ("observation", string value.observation);
          ("range", range value.range);
        ]
  | Normal.Annotation.Source_comment value ->
      assoc
        [
          ("kind", string "source-comment");
          ("observation", string value.observation);
          ("range", range value.range);
        ]
  | Normal.Annotation.Sidecar value ->
      [
        ("kind", string "sidecar");
        ("observation", string value.observation);
      ]
      |> add_optional "path" string value.path |> List.rev |> assoc
  | Normal.Annotation.Generated_index value ->
      assoc
        [
          ("kind", string "generated-index");
          ("observation", string value.observation);
        ]

let annotation (value : Normal.Annotation.t) =
  assoc
    [
      ("id", observation_scoped_id value.id);
      ("subject", region_ref value.subject);
      ("predicate", string value.predicate);
      ("object", annotation_object value.object_);
      ("provenance", list provenance value.provenance);
      ("materialization", list materialization value.materialization);
    ]

let edit (value : Normal.Patch.edit) =
  assoc
    [
      ("range", range value.range);
      ("replacement", string value.replacement);
    ]

let patch (value : Normal.Patch.t) =
  match value.operation with
  | Normal.Patch.Create { content } ->
      assoc
        [
          ("id", string value.id);
          ("operation", string "create");
          ("target", string value.target);
          ("resultingContentIdentity", content_identity value.resulting_identity);
          ("content", string content);
          ("reason", string value.reason);
          ("provenance", provenance value.provenance);
        ]
  | Normal.Patch.Edit { expected_identity; edits } ->
      assoc
        [
          ("id", string value.id);
          ("operation", string "edit");
          ("target", string value.target);
          ("expectedContentIdentity", content_identity expected_identity);
          ("resultingContentIdentity", content_identity value.resulting_identity);
          ("edits", list edit edits);
          ("reason", string value.reason);
          ("provenance", provenance value.provenance);
        ]

let snapshot_target (value : Normal.Snapshot.target) =
  [ ("origin", origin value.origin); ("selector", selector value.selector) ]
  |> add_interpreter value.interpreter
  |> List.rev |> assoc

let snapshot (value : Normal.Snapshot.t) =
  [
    ("target", snapshot_target value.target);
    ("observationIdentity", observation_identity value.observation_identity);
    ("observedAt", string value.observed_at);
  ]
  |> add_optional "regionFingerprint" string value.region_fingerprint
  |> add_optional "display" string value.display
  |> List.rev |> assoc

let diagnostic_scoped_id (value : Normal.Diagnostic.scoped_id) =
  assoc [ ("observation", string value.observation); ("local", string value.local) ]

let location (value : Normal.Diagnostic.location) =
  []
  |> add_optional "observation" string value.observation
  |> add_optional "region" diagnostic_scoped_id value.region
  |> add_optional "annotation" diagnostic_scoped_id value.annotation
  |> add_optional "range" range value.range
  |> List.rev |> assoc

let extension_failure (value : Normal.Diagnostic.extension_failure) =
  [
    ("operation", string value.operation);
    ("code", string value.code);
  ]
  |> add_optional "data" Fun.id value.data
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
  |> add_optional "extensionFailure" extension_failure value.extension_failure
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
  | Normal.Conflict.Missing_target -> assoc (common "missing-target")
  | Normal.Conflict.Target_already_exists detail ->
      assoc
        (common "target-already-exists"
        @ [ ("actual", content_identity detail.actual) ])
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

let changed_file (value : Normal.Command_result.changed_file) =
  match value.before with
  | None ->
      assoc
        [
          ("path", string value.path);
          ("after", content_identity value.after);
        ]
  | Some before ->
      assoc
        [
          ("path", string value.path);
          ("before", content_identity before);
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

let capability_applies_to (value : Normal.Capability.applies_to) =
  assoc
    [
      ("mediaTypes", list string value.media_types);
      ("pathGlobs", list string value.path_globs);
    ]

let capability_schemas (value : Normal.Capability.schemas) =
  []
  |> add_optional "selector" string value.selector
  |> add_optional "annotation" string value.annotation
  |> add_optional "options" string value.options
  |> List.rev |> assoc

let capability (value : Normal.Capability.t) =
  [
    ("type", string value.kind);
    ("name", string value.name);
    ("version", string value.version);
  ]
  |> add_optional "appliesTo" capability_applies_to value.applies_to
  |> add_optional "schemas" capability_schemas value.schemas
  |> List.rev |> assoc

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
    ("changedFiles", list changed_file value.changed_files);
    ("conflicts", list conflict value.conflicts);
    ("snapshots", list snapshot value.snapshots);
    ("observations", list observation value.observations);
    ("regions", list region value.regions);
    ("references", list reference value.references);
    ("annotations", list annotation value.annotations);
    ("capabilities", list capability value.capabilities);
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
