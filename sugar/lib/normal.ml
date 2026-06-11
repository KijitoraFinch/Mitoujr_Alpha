let schema_version = "1"

module Semantic_content_identity = Content_identity
module Semantic_selector = Selector
module Semantic_provenance = Provenance
module Semantic_diagnostic = Diagnostic
module Semantic_conflict = Conflict
module Semantic_command_result = Command_result
module Semantic_workspace_snapshot = Workspace_snapshot

type semantic_content_identity = Semantic_content_identity.t
type semantic_selector = Semantic_selector.t
type semantic_provenance = Semantic_provenance.t
type semantic_diagnostic = Semantic_diagnostic.t
type semantic_conflict = Semantic_conflict.t
type semantic_command_result = Semantic_command_result.t
type semantic_workspace_snapshot = Semantic_workspace_snapshot.t
type summary_value = Semantic_command_result.summary_value

module Content_identity = struct
  type t = {
    hash : string;
    size : int;
  }

  let normalize value =
    {
      hash = Semantic_content_identity.display_hash value;
      size = Semantic_content_identity.byte_length value;
    }
end

module Range = struct
  type t = {
    start : int;
    end_ : int;
  }

  let normalize value =
    { start = Text_range.start value; end_ = Text_range.end_ value }
end

module Selector = struct
  type t =
    | Whole_artifact
    | Region_id of string
    | Text_range of Range.t
    | Row_filter of { column : string; equals : string }

  let normalize = function
    | Semantic_selector.Whole_artifact -> Whole_artifact
    | Semantic_selector.Region_id id ->
        Region_id (Identifier.to_string id)
    | Semantic_selector.Text_range range ->
        Text_range (Range.normalize range)
    | Semantic_selector.Row_filter filter ->
        Row_filter { column = filter.column; equals = filter.equals }
end

module Origin = struct
  type t =
    | Workspace of string
    | Git of { repo : string; rev : string option; path : string }
    | Web of string
    | Generated of string
    | External of string

  let normalize = function
    | Artifact.Workspace path ->
        Workspace (Workspace_path.to_canonical_string path)
    | Artifact.Git value ->
        Git { repo = value.repo; rev = value.rev; path = value.path }
    | Artifact.Web url -> Web url
    | Artifact.Generated name -> Generated name
    | Artifact.External uri -> External uri
end

module Provenance = struct
  type t = {
    source : string;
    detail : string option;
  }

  let normalize value =
    {
      source = Semantic_provenance.source value;
      detail = Semantic_provenance.detail value;
    }
end

module Patch = struct
  type edit = {
    range : Range.t;
    replacement : string;
  }

  type t = {
    id : string;
    target : string;
    expected_identity : Content_identity.t;
    resulting_identity : Content_identity.t;
    edits : edit list;
    reason : string;
    provenance : Provenance.t;
  }

  let normalize_edit edit =
    {
      range = Text_edit.range edit |> Range.normalize;
      replacement = Text_edit.replacement edit;
    }

  let compare_edit left right =
    match Int.compare left.range.start right.range.start with
    | 0 -> (
        match Int.compare left.range.end_ right.range.end_ with
        | 0 -> String.compare left.replacement right.replacement
        | other -> other)
    | other -> other

  let normalize value =
    {
      id = Proposed_patch.id value |> Identifier.to_string;
      target =
        Proposed_patch.target value |> Workspace_path.to_canonical_string;
      expected_identity =
        Proposed_patch.expected_identity value |> Content_identity.normalize;
      resulting_identity =
        Proposed_patch.resulting_identity value |> Content_identity.normalize;
      edits =
        Proposed_patch.edits value |> List.map normalize_edit
        |> List.sort compare_edit;
      reason = Proposed_patch.reason value;
      provenance = Proposed_patch.provenance value |> Provenance.normalize;
    }
end

module Snapshot = struct
  type target = {
    artifact : Origin.t;
    selector : Selector.t option;
    interpreter : string option;
  }

  type t = {
    target : target;
    artifact_identity : Content_identity.t;
    region_fingerprint : string option;
    display : string option;
    observed_at : string;
  }

  let normalize value =
    let source_target = Resolution_snapshot.target value in
    {
      target =
        {
          artifact = Origin.normalize source_target.artifact;
          selector = Option.map Selector.normalize source_target.selector;
          interpreter = source_target.interpreter;
        };
      artifact_identity =
        Resolution_snapshot.artifact_identity value
        |> Content_identity.normalize;
      region_fingerprint = Resolution_snapshot.region_fingerprint value;
      display = Resolution_snapshot.display value;
      observed_at = Resolution_snapshot.observed_at value;
    }
end

module Diagnostic = struct
  type location = {
    artifact : string option;
    region : string option;
    annotation : string option;
    range : Range.t option;
  }

  type t = {
    code : string;
    default_severity : string;
    effective_severity : string;
    message : string;
    location : location option;
    suggested_fixes : Patch.t list;
  }

  let normalize_location (location : Semantic_diagnostic.location) =
    {
      artifact = Option.map Identifier.to_string location.artifact;
      region = Option.map Identifier.to_string location.region;
      annotation = Option.map Identifier.to_string location.annotation;
      range = Option.map Range.normalize location.range;
    }

  let compare left right =
    Stdlib.compare left right

  let normalize value =
    let code = Semantic_diagnostic.code value in
    {
      code = Semantic_diagnostic.code_string code;
      default_severity =
        Semantic_diagnostic.default_severity code
        |> Semantic_diagnostic.severity_string;
      effective_severity =
        Semantic_diagnostic.effective_severity value
        |> Semantic_diagnostic.severity_string;
      message = Semantic_diagnostic.message value;
      location =
        Option.map normalize_location
          (Semantic_diagnostic.location value);
      suggested_fixes =
        Semantic_diagnostic.suggested_fixes value
        |> List.map Patch.normalize
        |> List.sort Stdlib.compare;
    }
end

module Conflict = struct
  type detail =
    | Missing_artifact
    | Identity_mismatch of {
        expected : Content_identity.t;
        actual : Content_identity.t;
      }
    | Result_identity_mismatch of {
        declared : Content_identity.t;
        actual : Content_identity.t;
      }
    | Range_out_of_bounds of {
        range : Range.t;
        content_length : int;
      }
    | Overlapping_edits of {
        left : Range.t;
        right : Range.t;
      }

  type t = {
    patch_id : string;
    target : string;
    detail : detail;
  }

  let normalize value =
    let detail =
      match value with
      | Semantic_conflict.Missing_artifact _ -> Missing_artifact
      | Semantic_conflict.Identity_mismatch value ->
          Identity_mismatch
            {
              expected = Content_identity.normalize value.expected;
              actual = Content_identity.normalize value.actual;
            }
      | Semantic_conflict.Result_identity_mismatch value ->
          Result_identity_mismatch
            {
              declared = Content_identity.normalize value.declared;
              actual = Content_identity.normalize value.actual;
            }
      | Semantic_conflict.Range_out_of_bounds value ->
          Range_out_of_bounds
            {
              range = Range.normalize value.range;
              content_length = value.content_length;
            }
      | Semantic_conflict.Overlapping_edits value ->
          Overlapping_edits
            {
              left = Range.normalize value.left;
              right = Range.normalize value.right;
            }
    in
    {
      patch_id =
        Semantic_conflict.patch_id value |> Identifier.to_string;
      target =
        Semantic_conflict.target value
        |> Workspace_path.to_canonical_string;
      detail;
    }
end

module Workspace_snapshot = struct
  type file = {
    path : string;
    content_hex : string;
    content_identity : Content_identity.t;
  }

  type t = {
    files : file list;
  }

  let hex = "0123456789abcdef"

  let content_hex content =
    let buffer = Buffer.create (String.length content * 2) in
    String.iter
      (fun char ->
        let byte = Char.code char in
        Buffer.add_char buffer hex.[byte lsr 4];
        Buffer.add_char buffer hex.[byte land 0x0f])
      content;
    Buffer.contents buffer

  let normalize_file file =
    {
      path =
        Semantic_workspace_snapshot.file_path file
        |> Workspace_path.to_canonical_string;
      content_hex =
        Semantic_workspace_snapshot.file_content file |> content_hex;
      content_identity =
        Semantic_workspace_snapshot.file_identity file
        |> Content_identity.normalize;
    }

  let normalize value =
    { files = Semantic_workspace_snapshot.files value |> List.map normalize_file }
end

module Command_result = struct
  type changed_artifact = {
    path : string;
    before : Content_identity.t;
    after : Content_identity.t;
  }

  type t = {
    schema_version : string;
    command : string;
    status : string;
    diagnostics : Diagnostic.t list;
    patches : Patch.t list;
    changed_artifacts : changed_artifact list;
    conflicts : Conflict.t list;
    snapshots : Snapshot.t list;
    summary : (string * summary_value) list option;
    exit_class : string;
  }

  let normalize_changed (value : Semantic_command_result.changed_artifact) =
    {
      path = Workspace_path.to_canonical_string value.path;
      before = Content_identity.normalize value.before;
      after = Content_identity.normalize value.after;
    }

  let normalize value =
    {
      schema_version;
      command = Semantic_command_result.command value;
      status =
        Semantic_command_result.status value
        |> Semantic_command_result.status_string;
      diagnostics =
        Semantic_command_result.diagnostics value
        |> List.map Diagnostic.normalize
        |> List.sort Diagnostic.compare;
      patches =
        Semantic_command_result.patches value |> List.map Patch.normalize
        |> List.sort Stdlib.compare;
      changed_artifacts =
        Semantic_command_result.changed_artifacts value
        |> List.map normalize_changed
        |> List.sort Stdlib.compare;
      conflicts =
        Semantic_command_result.conflicts value
        |> List.map Conflict.normalize |> List.sort Stdlib.compare;
      snapshots =
        Semantic_command_result.snapshots value
        |> List.map Snapshot.normalize |> List.sort Stdlib.compare;
      summary =
        Option.map
          (List.sort (fun (left, _) (right, _) -> String.compare left right))
          (Semantic_command_result.summary value);
      exit_class =
        Semantic_command_result.exit_class value
        |> Semantic_command_result.exit_class_string;
    }
end
