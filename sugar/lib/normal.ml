let schema_version = "7"

module Semantic_content_identity = Content_identity
module Semantic_selector = Selector
module Semantic_provenance = Provenance
module Semantic_diagnostic = Diagnostic
module Semantic_conflict = Conflict
module Semantic_command_result = Command_result
module Semantic_workspace_snapshot = Workspace_snapshot
module Semantic_observation = Observation
module Semantic_region = Region
module Semantic_reference = Reference
module Semantic_annotation = Annotation
module Semantic_capability = Capability
module Semantic_region_address = Region_address
module Semantic_region_ref = Region_ref
module Semantic_expectation = Expectation

type semantic_content_identity = Semantic_content_identity.t
type semantic_selector = Semantic_selector.t
type semantic_provenance = Semantic_provenance.t
type semantic_diagnostic = Semantic_diagnostic.t
type semantic_conflict = Semantic_conflict.t
type semantic_command_result = Semantic_command_result.t
type semantic_workspace_snapshot = Semantic_workspace_snapshot.t
type semantic_observation = Semantic_observation.t
type semantic_region = Semantic_region.t
type semantic_reference = Semantic_reference.t
type semantic_annotation = Semantic_annotation.t
type semantic_capability = Semantic_capability.t
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
  type literal =
    | String of string
    | Int of int
    | Bool of bool

  type t =
    | Whole_observation
    | Region_id of string
    | Text_range of Range.t
    | Row_filter of { where : (string * literal) list }
    | Extension of { schema : string; value : Yojson.Safe.t }

  let normalize_literal = function
    | Semantic_selector.Literal.String value -> String value
    | Semantic_selector.Literal.Int value -> Int value
    | Semantic_selector.Literal.Bool value -> Bool value

  let normalize = function
    | Semantic_selector.Whole_observation -> Whole_observation
    | Semantic_selector.Region_id id ->
        Region_id (Identifier.to_string id)
    | Semantic_selector.Text_range range ->
        Text_range (Range.normalize range)
    | Semantic_selector.Row_filter filter ->
        Row_filter
          {
            where =
              Semantic_selector.Row_filter.conditions filter
              |> List.map (fun (field, literal) ->
                     ( Semantic_selector.Field_name.to_string field,
                       normalize_literal literal ));
          }
    | Semantic_selector.Extension extension ->
        Extension
          {
            schema = Semantic_selector.Extension.schema extension;
            value = Semantic_selector.Extension.value extension;
          }
end

module Origin = struct
  type t =
    | Workspace of string
    | Git of { repo : string; rev : string option; path : string }
    | Web of string
    | Generated of string
    | External of string
    | Extension of { provider : string; locator : string }

  let normalize = function
    | Origin.Workspace path ->
        Workspace (Workspace_path.to_canonical_string path)
    | Origin.Git value ->
        Git { repo = value.repo; rev = value.rev; path = value.path }
    | Origin.Web url -> Web url
    | Origin.Generated name -> Generated name
    | Origin.External uri -> External uri
    | Origin.Extension value ->
        Extension { provider = value.provider; locator = value.locator }
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

module Observation_type = struct
  type t = {
    name : string;
    version : string;
  }

  let normalize value =
    {
      name = Observation_type.name value;
      version = Observation_type.version value;
    }
end

module Observation_identity = struct
  type t = {
    observation_type : Observation_type.t;
    key : string;
  }

  let normalize value =
    {
      observation_type =
        Observation_identity.observation_type value
        |> Observation_type.normalize;
      key = Observation_identity.key value;
    }
end

module Observation = struct
  type t = {
    id : string;
    origin : Origin.t;
    identity : Observation_identity.t;
    content_identity : Content_identity.t option;
  }

  let normalize value =
    {
      id = Semantic_observation.id value |> Observation_id.to_string;
      origin = Semantic_observation.origin value |> Origin.normalize;
      identity =
        Semantic_observation.identity value |> Observation_identity.normalize;
      content_identity =
        Semantic_observation.content_identity value
        |> Option.map Content_identity.normalize;
    }
end

module Scoped_id = struct
  type t = {
    observation : string;
    local : string;
  }

  let make observation local =
    {
      observation = Observation_id.to_string observation;
      local = Identifier.to_string local;
    }

  let region value = make (Region_id.observation value) (Region_id.local value)

  let reference value =
    make (Reference_id.observation value) (Reference_id.local value)

  let annotation value =
    make (Annotation_id.observation value) (Annotation_id.local value)
end

module Interpreter_identity = struct
  type t = {
    name : string;
    version : string;
  }

  let normalize value =
    { name = Interpreter.name value; version = Interpreter.version value }
end

module Region_address = struct
  type t = {
    origin : Origin.t;
    selector : Selector.t;
    interpreter : Interpreter_identity.t option;
  }

  let normalize value =
    {
      origin = Semantic_region_address.origin value |> Origin.normalize;
      selector = Semantic_region_address.selector value |> Selector.normalize;
      interpreter =
        Semantic_region_address.interpreter_identity value
        |> Option.map Interpreter_identity.normalize;
    }
end

module Region_ref = struct
  type t = Resolved of Scoped_id.t | Address of Region_address.t

  let normalize = function
    | Semantic_region_ref.Resolved id -> Resolved (Scoped_id.region id)
    | Semantic_region_ref.Address address ->
        Address (Region_address.normalize address)
end

module Region = struct
  type t = {
    id : Scoped_id.t;
    selector : Selector.t;
    interpreter : Interpreter_identity.t option;
    summary : string option;
    range : Range.t option;
    fingerprint : string option;
  }

  let normalize value =
    {
      id = Semantic_region.id value |> Scoped_id.region;
      selector = Semantic_region.selector value |> Selector.normalize;
      interpreter =
        Semantic_region.interpreter_identity value
        |> Option.map Interpreter_identity.normalize;
      summary = Semantic_region.summary value;
      range = Option.map Range.normalize (Semantic_region.range value);
      fingerprint = Semantic_region.fingerprint value;
    }
end


module Expectation = struct
  type t = Digest of string

  let normalize = function
    | Semantic_expectation.Digest digest ->
        Digest (Content_digest.to_string digest)
end

module Reference = struct
  type t = {
    id : Scoped_id.t;
    target : Region_address.t;
    binding : string;
    expectations : Expectation.t list;
    provenance : Provenance.t list;
  }

  let binding = function
    | Semantic_reference.Pinned -> "pinned"
    | Semantic_reference.Tracking -> "tracking"
    | Semantic_reference.Floating -> "floating"

  let normalize value =
    {
      id = Semantic_reference.id value |> Scoped_id.reference;
      target = Semantic_reference.target value |> Region_address.normalize;
      binding = Semantic_reference.binding value |> binding;
      expectations =
        Semantic_reference.expectations value |> List.map Expectation.normalize
        |> List.sort Stdlib.compare;
      provenance =
        Semantic_reference.provenance value |> List.map Provenance.normalize
        |> List.sort Stdlib.compare;
    }
end

module Annotation = struct
  type object_ =
    | Region_object of Region_ref.t
    | Reference_object of Scoped_id.t
    | Literal of string

  type materialization =
    | Markdown_inline of { observation : string; range : Range.t }
    | Source_comment of { observation : string; range : Range.t }
    | Sidecar of { observation : string; path : string option }
    | Generated_index of { observation : string }

  type t = {
    id : Scoped_id.t;
    subject : Region_ref.t;
    predicate : string;
    object_ : object_;
    provenance : Provenance.t list;
    materialization : materialization list;
  }

  let normalize_object = function
    | Semantic_annotation.Region_object value ->
        Region_object (Region_ref.normalize value)
    | Semantic_annotation.Reference_object value ->
        Reference_object (Scoped_id.reference value)
    | Semantic_annotation.Literal value -> Literal value

  let normalize_materialization = function
    | Semantic_annotation.Markdown_inline { observation; range } ->
        Markdown_inline
          {
            observation = Observation_id.to_string observation;
            range = Range.normalize range;
          }
    | Semantic_annotation.Source_comment { observation; range } ->
        Source_comment
          {
            observation = Observation_id.to_string observation;
            range = Range.normalize range;
          }
    | Semantic_annotation.Sidecar { observation; path } ->
        Sidecar
          {
            observation = Observation_id.to_string observation;
            path = Option.map Workspace_path.to_canonical_string path;
          }
    | Semantic_annotation.Generated_index { observation } ->
        Generated_index { observation = Observation_id.to_string observation }

  let normalize value =
    {
      id = Semantic_annotation.id value |> Scoped_id.annotation;
      subject =
        (match Semantic_annotation.subject value with
        | Semantic_annotation.Region value -> Region_ref.normalize value);
      predicate = Semantic_annotation.predicate value;
      object_ = Semantic_annotation.object_ value |> normalize_object;
      provenance =
        Semantic_annotation.provenance value |> List.map Provenance.normalize
        |> List.sort Stdlib.compare;
      materialization =
        Semantic_annotation.materialization value
        |> List.map normalize_materialization |> List.sort Stdlib.compare;
    }
end

module Patch = struct
  type edit = {
    range : Range.t;
    replacement : string;
  }

  type operation =
    | Create of { content : string }
    | Edit of {
        expected_identity : Content_identity.t;
        edits : edit list;
      }

  type t = {
    id : string;
    target : string;
    operation : operation;
    resulting_identity : Content_identity.t;
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
    let operation =
      match Proposed_patch.operation value with
      | Proposed_patch.Create { content } -> Create { content }
      | Proposed_patch.Edit { expected_identity; edits } ->
          Edit
            {
              expected_identity = Content_identity.normalize expected_identity;
              edits =
                edits |> List.map normalize_edit |> List.sort compare_edit;
            }
    in
    {
      id = Proposed_patch.id value |> Patch_id.to_string;
      target =
        Proposed_patch.target value |> Workspace_path.to_canonical_string;
      operation;
      resulting_identity =
        Proposed_patch.resulting_identity value |> Content_identity.normalize;
      reason = Proposed_patch.reason value;
      provenance = Proposed_patch.provenance value |> Provenance.normalize;
    }
end

module Snapshot = struct
  type target = {
    origin : Origin.t;
    selector : Selector.t;
    interpreter : Interpreter_identity.t option;
  }

  type t = {
    target : target;
    observation_identity : Observation_identity.t;
    region_fingerprint : string option;
    display : string option;
    observed_at : string;
  }

  let normalize value =
    let source_target = Resolution_snapshot.target value in
    {
      target =
        {
          origin =
            Semantic_region_address.origin source_target |> Origin.normalize;
          selector =
            Semantic_region_address.selector source_target |> Selector.normalize;
          interpreter =
            Semantic_region_address.interpreter_identity source_target
            |> Option.map Interpreter_identity.normalize;
        };
      observation_identity =
        Resolution_snapshot.observation_identity value
        |> Observation_identity.normalize;
      region_fingerprint = Resolution_snapshot.region_fingerprint value;
      display = Resolution_snapshot.display value;
      observed_at = Resolution_snapshot.observed_at value;
    }
end

module Diagnostic = struct
  type scoped_id = {
    observation : string;
    local : string;
  }

  type location = {
    observation : string option;
    region : scoped_id option;
    annotation : scoped_id option;
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

  let normalize_region_id value =
    {
      observation = Region_id.observation value |> Observation_id.to_string;
      local = Region_id.local value |> Identifier.to_string;
    }

  let normalize_annotation_id value =
    {
      observation = Annotation_id.observation value |> Observation_id.to_string;
      local = Annotation_id.local value |> Identifier.to_string;
    }

  let normalize_location (location : Semantic_diagnostic.location) =
    {
      observation = Option.map Observation_id.to_string location.observation;
                region = Option.map normalize_region_id location.region;
                annotation =
                  Option.map normalize_annotation_id location.annotation;
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
    | Missing_target
    | Target_already_exists of { actual : Content_identity.t }
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
    | Filesystem_safety of { reason : string }

  type t = {
    patch_id : string;
    target : string;
    detail : detail;
  }

  let normalize value =
    let detail =
      match value with
      | Semantic_conflict.Missing_target _ -> Missing_target
      | Semantic_conflict.Target_already_exists value ->
          Target_already_exists
            { actual = Content_identity.normalize value.actual }
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
      | Semantic_conflict.Filesystem_safety value ->
          Filesystem_safety
            {
              reason =
                Semantic_conflict.filesystem_safety_reason_string
                  value.reason;
            }
    in
    {
      patch_id =
        Semantic_conflict.patch_id value |> Patch_id.to_string;
      target =
        Semantic_conflict.target value
        |> Workspace_path.to_canonical_string;
      detail;
    }
end

module Capability = struct
  type applies_to = {
    media_types : string list;
    path_globs : string list;
  }

  type schemas = {
    selector : string option;
    annotation : string option;
    options : string option;
  }

  type t = {
    kind : string;
    name : string;
    version : string;
    applies_to : applies_to option;
    schemas : schemas option;
  }

  let normalize value =
    {
      kind = Semantic_capability.kind value |> Semantic_capability.kind_string;
      name = Semantic_capability.name value;
      version = Semantic_capability.version value;
      applies_to =
        Option.map
          (fun (value : Semantic_capability.applies_to) ->
            {
              media_types = List.sort String.compare value.media_types;
              path_globs = List.sort String.compare value.path_globs;
            })
          (Semantic_capability.applies_to value);
      schemas =
        Option.map
          (fun (value : Semantic_capability.schemas) ->
            {
              selector = value.selector;
              annotation = value.annotation;
              options = value.options;
            })
          (Semantic_capability.schemas value);
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
  type changed_file = {
    path : string;
    before : Content_identity.t option;
    after : Content_identity.t;
  }

  type t = {
    schema_version : string;
    command : string;
    status : string;
    diagnostics : Diagnostic.t list;
    patches : Patch.t list;
    changed_files : changed_file list;
    conflicts : Conflict.t list;
    snapshots : Snapshot.t list;
    observations : Observation.t list;
    regions : Region.t list;
    references : Reference.t list;
    annotations : Annotation.t list;
    capabilities : Capability.t list;
    summary : (string * summary_value) list option;
    exit_class : string;
  }

  let normalize_changed (value : Semantic_command_result.changed_file) =
    {
      path = Workspace_path.to_canonical_string value.path;
      before = Option.map Content_identity.normalize value.before;
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
      changed_files =
        Semantic_command_result.changed_files value
        |> List.map normalize_changed
        |> List.sort Stdlib.compare;
      conflicts =
        Semantic_command_result.conflicts value
        |> List.map Conflict.normalize |> List.sort Stdlib.compare;
      snapshots =
        Semantic_command_result.snapshots value
        |> List.map Snapshot.normalize |> List.sort Stdlib.compare;
      observations =
        Semantic_command_result.observations value
        |> List.map Observation.normalize |> List.sort Stdlib.compare;
      regions =
        Semantic_command_result.regions value
        |> List.map Region.normalize |> List.sort Stdlib.compare;
      references =
        Semantic_command_result.references value
        |> List.map Reference.normalize |> List.sort Stdlib.compare;
      annotations =
        Semantic_command_result.annotations value
        |> List.map Annotation.normalize |> List.sort Stdlib.compare;
      capabilities =
        Semantic_command_result.capabilities value
        |> List.map Capability.normalize |> List.sort Stdlib.compare;
      summary =
        Option.map
          (List.sort (fun (left, _) (right, _) -> String.compare left right))
          (Semantic_command_result.summary value);
      exit_class =
        Semantic_command_result.exit_class value
        |> Semantic_command_result.exit_class_string;
    }
end
