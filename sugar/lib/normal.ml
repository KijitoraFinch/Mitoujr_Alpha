let schema_version = "11"

module Semantic_content_identity = Content_identity
module Semantic_selector = Selector
module Semantic_provenance = Provenance
module Semantic_diagnostic = Diagnostic
module Semantic_conflict = Conflict
module Semantic_command_result = Command_result
module Semantic_workspace_snapshot = Workspace_snapshot
module Semantic_observation = Observation
module Semantic_observation_type = Observation_type
module Semantic_region = Region
module Semantic_reference = Reference
module Semantic_annotation = Annotation
module Semantic_capability = Capability
module Semantic_region_address = Region_address
module Semantic_region_ref = Region_ref
module Semantic_expectation = Expectation
module Semantic_schema_value = Schema_value

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

module Schema_value = struct
  type t = {
    schema : string;
    value : Yojson.Safe.t;
  }

  let normalize value =
    {
      schema = Semantic_schema_value.schema value;
      value =
        Semantic_schema_value.value value |> Normalized_value.to_yojson;
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
  type observer_identity = {
    name : string;
    version : string;
  }

  type t =
    | Workspace of string
    | Git of { repo : string; rev : string option; path : string }
    | Web of string
    | Generated of string
    | External of string
    | Extension of {
        observer : observer_identity;
        locator : Yojson.Safe.t;
      }

  let normalize = function
    | Origin.Workspace path ->
        Workspace (Workspace_path.to_canonical_string path)
    | Origin.Git value ->
        Git { repo = value.repo; rev = value.rev; path = value.path }
    | Origin.Web url -> Web url
    | Origin.Generated name -> Generated name
    | Origin.External uri -> External uri
    | Origin.Extension value ->
        Extension
          {
            observer =
              {
                name = Resource_observer.name value.observer;
                version = Resource_observer.version value.observer;
              };
            locator = Normalized_value.to_yojson value.locator;
          }
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

  let normalize (value : Semantic_observation_type.t) : t =
    {
      name = Semantic_observation_type.name value;
      version = Semantic_observation_type.version value;
    }
end

module Normal_observation_type = Observation_type

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
  type representation =
    | Bytes
    | Structured of { schema : string; value : Yojson.Safe.t }

  type t = {
    id : string;
    origin : Origin.t;
    identity : Observation_identity.t;
    representation : representation;
    content_identity : Content_identity.t option;
  }

  let normalize value =
    {
      id = Semantic_observation.id value |> Observation_id.to_string;
      origin = Semantic_observation.origin value |> Origin.normalize;
      identity =
        Semantic_observation.identity value |> Observation_identity.normalize;
      representation =
        (match Semantic_observation.representation value with
        | Semantic_observation.Bytes _ -> Bytes
        | Semantic_observation.Structured structured ->
            Structured
              {
                schema = structured.schema;
                value = Normalized_value.to_yojson structured.value;
              });
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

end

module Origin_scoped_id = struct
  type t = {
    scope : Origin.t;
    local : string;
  }

  let reference value =
    {
      scope = Reference_id.scope value |> Origin.normalize;
      local = Reference_id.local value |> Identifier.to_string;
    }

  let annotation value =
    {
      scope = Annotation_id.scope value |> Origin.normalize;
      local = Annotation_id.local value |> Identifier.to_string;
    }
end

module Interpreter_identity = struct
  type t = {
    name : string;
    version : string;
  }

  let normalize value =
    { name = Interpreter.name value; version = Interpreter.version value }
end

module Expectation = struct
  type t =
    | Observation_identity of Observation_identity.t
    | Content_identity of Content_identity.t
    | Revision of Schema_value.t
    | Fingerprint of Schema_value.t

  let normalize = function
    | Semantic_expectation.Observation_identity identity ->
        Observation_identity (Observation_identity.normalize identity)
    | Semantic_expectation.Content_identity identity ->
        Content_identity (Content_identity.normalize identity)
    | Semantic_expectation.Revision revision ->
        Revision (Schema_value.normalize revision)
    | Semantic_expectation.Fingerprint fingerprint ->
        Fingerprint (Schema_value.normalize fingerprint)
end

module Region_address = struct
  type t = {
    origin : Origin.t;
    selector : Selector.t;
    interpreter : Interpreter_identity.t option;
    expectation : Expectation.t option;
  }

  let normalize value =
    {
      origin = Semantic_region_address.origin value |> Origin.normalize;
      selector = Semantic_region_address.selector value |> Selector.normalize;
      interpreter =
        Semantic_region_address.interpreter_identity value
        |> Option.map Interpreter_identity.normalize;
      expectation =
        Semantic_region_address.expectation value
        |> Option.map Expectation.normalize;
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
    fingerprint : Schema_value.t option;
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
      fingerprint =
        Semantic_region.fingerprint value |> Option.map Schema_value.normalize;
    }
end

module Reference = struct
  type t = {
    id : Origin_scoped_id.t;
    target : Region_address.t;
    binding : string;
    expectations : Expectation.t list;
  }

  let binding = function
    | Semantic_reference.Pinned -> "pinned"
    | Semantic_reference.Tracking -> "tracking"
    | Semantic_reference.Floating -> "floating"

  let normalize value =
    {
      id = Semantic_reference.id value |> Origin_scoped_id.reference;
      target = Semantic_reference.target value |> Region_address.normalize;
      binding = Semantic_reference.binding value |> binding;
      expectations =
        Semantic_reference.expectations value |> List.map Expectation.normalize
        |> List.sort Stdlib.compare;
    }
end

module Annotation = struct
  type object_ =
    | Region_object of Region_ref.t
    | Reference_object of Origin_scoped_id.t
    | Literal of string

  type t = {
    id : Origin_scoped_id.t;
    subject : Region_ref.t;
    predicate : string;
    object_ : object_;
  }

  let normalize_object = function
    | Semantic_annotation.Region_object value ->
        Region_object (Region_ref.normalize value)
    | Semantic_annotation.Reference_object value ->
        Reference_object (Origin_scoped_id.reference value)
    | Semantic_annotation.Literal value -> Literal value

  let normalize value =
    {
      id = Semantic_annotation.id value |> Origin_scoped_id.annotation;
      subject = Semantic_annotation.subject value |> Region_ref.normalize;
      predicate = Semantic_annotation.predicate value;
      object_ = Semantic_annotation.object_ value |> normalize_object;
    }
end

module Structured_location = struct
  type t = {
    schema : string;
    value : Yojson.Safe.t;
  }

  let normalize value =
    {
      schema = Structured_location.schema value;
      value = Structured_location.value value;
    }
end

module Observation_encoding = struct
  type t = {
    name : string;
    version : string;
  }

  let normalize value =
    {
      name = Observation_encoding.name value;
      version = Observation_encoding.version value;
    }
end

module Source_location = struct
  type observation_locator =
    | Byte_range of Range.t
    | Structured of Structured_location.t

  type t =
    | In_observation of {
        observation : string;
        locator : observation_locator;
        encoding : Observation_encoding.t;
      }
    | In_sidecar of {
        path : string;
        content_identity : Content_identity.t;
        locator : Structured_location.t;
        ownership : string;
      }

  let normalize = function
    | Source_location.In_observation source ->
        In_observation
          {
            observation = Observation_id.to_string source.observation;
            locator =
              (match source.locator with
              | Source_location.Byte_range range ->
                  Byte_range (Range.normalize range)
              | Source_location.Structured location ->
                  Structured (Structured_location.normalize location));
            encoding = Observation_encoding.normalize source.encoding;
          }
    | Source_location.In_sidecar source ->
        In_sidecar
          {
            path = Workspace_path.to_canonical_string source.path;
            content_identity = Content_identity.normalize source.content_identity;
            locator = Structured_location.normalize source.locator;
            ownership =
              (match source.ownership with
              | Source_location.Authored -> "authored"
              | Source_location.Derived -> "derived");
          }
end

module Annotation_occurrence = struct
  type t = {
    annotation : Annotation.t;
    source : Source_location.t;
  }

  let normalize value =
    {
      annotation = Annotation_occurrence.annotation value |> Annotation.normalize;
      source = Annotation_occurrence.source value |> Source_location.normalize;
    }
end

module Reference_definition = struct
  type t = {
    reference : Reference.t;
    source : Source_location.t;
  }

  let normalize value =
    {
      reference =
        Reference_definition_occurrence.reference value |> Reference.normalize;
      source =
        Reference_definition_occurrence.source value |> Source_location.normalize;
    }
end

module Reference_use = struct
  type source_region = Whole_observation | Region of Scoped_id.t
  type target = Named of Origin_scoped_id.t | Direct of Region_address.t

  type t = {
    source_observation : string;
    source_region : source_region;
    source_range : Range.t;
    target : target;
  }

  let normalize value =
    {
      source_observation =
        Reference_use.source_observation value |> Observation_id.to_string;
      source_region =
        (match Reference_use.source_region value with
        | Reference_use.Whole_observation -> Whole_observation
        | Reference_use.Region id -> Region (Scoped_id.region id));
      source_range = Reference_use.source_range value |> Range.normalize;
      target =
        (match Reference_use.target value with
        | Reference_use.Named id ->
            Named (Origin_scoped_id.reference id)
        | Reference_use.Direct address ->
            Direct (Region_address.normalize address));
    }
end

module Sidecar_snapshot = struct
  type t = {
    path : string;
    content_identity : Content_identity.t;
  }

  let normalize value =
    {
      path = Sidecar_snapshot.path value |> Workspace_path.to_canonical_string;
      content_identity =
        Sidecar_snapshot.content_identity value |> Content_identity.normalize;
    }
end

module Coverage = struct
  type t = {
    primary_resources : int;
    observed : int;
    interpreted : int;
    unsupported : int;
    failed : int;
    metadata_discovered : int;
    metadata_decoded : int;
    metadata_failed : int;
    complete : bool;
  }

  let normalize value =
    {
      primary_resources = Coverage.primary_resources value;
      observed = Coverage.observed value;
      interpreted = Coverage.interpreted value;
      unsupported = Coverage.unsupported value;
      failed = Coverage.failed value;
      metadata_discovered = Coverage.metadata_discovered value;
      metadata_decoded = Coverage.metadata_decoded value;
      metadata_failed = Coverage.metadata_failed value;
      complete = Coverage.complete value;
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
    expectation : Expectation.t option;
  }

  type t = {
    target : target;
    observation_identity : Observation_identity.t;
    region_fingerprint : Schema_value.t option;
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
          expectation =
            Semantic_region_address.expectation source_target
            |> Option.map Expectation.normalize;
        };
      observation_identity =
        Resolution_snapshot.observation_identity value
        |> Observation_identity.normalize;
      region_fingerprint =
        Resolution_snapshot.region_fingerprint value
        |> Option.map Schema_value.normalize;
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
    annotation : Origin_scoped_id.t option;
    range : Range.t option;
  }

  type extension_failure = {
    operation : string;
    code : string;
    data : Yojson.Safe.t option;
  }

  type t = {
    code : string;
    default_severity : string;
    effective_severity : string;
    message : string;
    location : location option;
    extension_failure : extension_failure option;
    suggested_fixes : Patch.t list;
  }

  let normalize_region_id value =
    {
      observation = Region_id.observation value |> Observation_id.to_string;
      local = Region_id.local value |> Identifier.to_string;
    }

  let normalize_annotation_id value =
    Origin_scoped_id.annotation value

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

  let normalize_extension_failure value =
    {
      operation =
        Extension_failure.operation value
        |> Extension_failure.operation_string;
      code = Extension_failure.code value;
      data = Extension_failure.data value;
    }

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
      extension_failure =
        Option.map normalize_extension_failure
          (Semantic_diagnostic.extension_failure value);
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
    observation_types : Observation_type.t list;
    path_globs : string list;
  }

  type schemas = {
    selector_schemas : string list;
    result_schemas : string list;
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
            ({
              observation_types =
                value.observation_types
                |> List.map Normal_observation_type.normalize
                |> List.sort (fun
                     (left : Normal_observation_type.t)
                     (right : Normal_observation_type.t) ->
                       match String.compare left.name right.name with
                       | 0 -> String.compare left.version right.version
                       | other -> other);
              path_globs = List.sort String.compare value.path_globs;
            }
              : applies_to))
          (Semantic_capability.applies_to value);
      schemas =
        Option.map
          (fun (value : Semantic_capability.schemas) ->
            ({
              selector_schemas = List.sort String.compare value.selector_schemas;
              result_schemas = List.sort String.compare value.result_schemas;
            }
              : schemas))
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
    sidecar_snapshots : Sidecar_snapshot.t list;
    regions : Region.t list;
    references : Reference.t list;
    annotations : Annotation.t list;
    reference_definitions : Reference_definition.t list;
    reference_uses : Reference_use.t list;
    annotation_occurrences : Annotation_occurrence.t list;
    capabilities : Capability.t list;
    coverage : Coverage.t;
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
      sidecar_snapshots =
        Semantic_command_result.sidecar_snapshots value
        |> List.map Sidecar_snapshot.normalize |> List.sort Stdlib.compare;
      regions =
        Semantic_command_result.regions value
        |> List.map Region.normalize |> List.sort Stdlib.compare;
      references =
        Semantic_command_result.references value
        |> List.map Reference.normalize |> List.sort Stdlib.compare;
      annotations =
        Semantic_command_result.annotations value
        |> List.map Annotation.normalize |> List.sort Stdlib.compare;
      reference_definitions =
        Semantic_command_result.reference_definitions value
        |> List.map Reference_definition.normalize |> List.sort Stdlib.compare;
      reference_uses =
        Semantic_command_result.reference_uses value
        |> List.map Reference_use.normalize |> List.sort Stdlib.compare;
      annotation_occurrences =
        Semantic_command_result.annotation_occurrences value
        |> List.map Annotation_occurrence.normalize |> List.sort Stdlib.compare;
      capabilities =
        Semantic_command_result.capabilities value
        |> List.map Capability.normalize |> List.sort Stdlib.compare;
      coverage =
        Semantic_command_result.coverage value |> Coverage.normalize;
      summary =
        Option.map
          (List.sort (fun (left, _) (right, _) -> String.compare left right))
          (Semantic_command_result.summary value);
      exit_class =
        Semantic_command_result.exit_class value
        |> Semantic_command_result.exit_class_string;
    }
end
