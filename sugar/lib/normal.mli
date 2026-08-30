val schema_version : string

type semantic_content_identity = Content_identity.t
type semantic_selector = Selector.t
type semantic_provenance = Provenance.t
type semantic_diagnostic = Diagnostic.t
type semantic_conflict = Conflict.t
type semantic_command_result = Command_result.t
type semantic_workspace_snapshot = Workspace_snapshot.t
type semantic_observation = Observation.t
type semantic_region = Region.t
type semantic_reference = Reference.t
type semantic_annotation = Annotation.t
type semantic_capability = Capability.t
type summary_value = Command_result.summary_value

module Content_identity : sig
  type t = {
    hash : string;
    size : int;
  }

  val normalize : semantic_content_identity -> t
end

module Range : sig
  type t = {
    start : int;
    end_ : int;
  }

  val normalize : Text_range.t -> t
end

module Selector : sig
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

  val normalize : semantic_selector -> t
end

module Origin : sig
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

  val normalize : Observation.origin -> t
end

module Provenance : sig
  type t = {
    source : string;
    detail : string option;
  }

  val normalize : semantic_provenance -> t
end

module Observation_type : sig
  type t = {
    name : string;
    version : string;
  }

  val normalize : Observation_type.t -> t
end

module Observation_identity : sig
  type t = {
    observation_type : Observation_type.t;
    key : string;
  }

  val normalize : Observation_identity.t -> t
end

module Observation : sig
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

  val normalize : semantic_observation -> t
end

module Scoped_id : sig
  type t = {
    observation : string;
    local : string;
  }
end

module Origin_scoped_id : sig
  type t = {
    scope : Origin.t;
    local : string;
  }

  val reference : Reference_id.t -> t
  val annotation : Annotation_id.t -> t
end

module Interpreter_identity : sig
  type t = {
    name : string;
    version : string;
  }
end

module Region_address : sig
  type t = {
    origin : Origin.t;
    selector : Selector.t;
    interpreter : Interpreter_identity.t option;
  }

  val normalize : Region_address.t -> t
end

module Region_ref : sig
  type t = Resolved of Scoped_id.t | Address of Region_address.t

  val normalize : Region_ref.t -> t
end

module Region : sig
  type t = {
    id : Scoped_id.t;
    selector : Selector.t;
    interpreter : Interpreter_identity.t option;
    summary : string option;
    range : Range.t option;
    fingerprint : string option;
  }

  val normalize : semantic_region -> t
end

module Expectation : sig
  type t = Digest of string
end

module Reference : sig
  type t = {
    id : Origin_scoped_id.t;
    target : Region_address.t;
    binding : string;
    expectations : Expectation.t list;
  }

  val normalize : semantic_reference -> t
end

module Annotation : sig
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

  val normalize : semantic_annotation -> t
end

module Structured_location : sig
  type t = {
    schema : string;
    value : Yojson.Safe.t;
  }
end

module Observation_encoding : sig
  type t = {
    name : string;
    version : string;
  }
end

module Source_location : sig
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
end

module Annotation_occurrence : sig
  type t = {
    annotation : Annotation.t;
    source : Source_location.t;
  }


  val normalize : Annotation_occurrence.t -> t
end

module Reference_definition : sig
  type t = {
    reference : Reference.t;
    source : Source_location.t;
  }


  val normalize : Reference_definition_occurrence.t -> t
end

module Reference_use : sig
  type source_region = Whole_observation | Region of Scoped_id.t
  type target = Named of Origin_scoped_id.t | Direct of Region_address.t

  type t = {
    source_observation : string;
    source_region : source_region;
    source_range : Range.t;
    target : target;
  }


  val normalize : Reference_use.t -> t
end

module Sidecar_snapshot : sig
  type t = {
    path : string;
    content_identity : Content_identity.t;
  }


  val normalize : Sidecar_snapshot.t -> t
end

module Coverage : sig
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


  val normalize : Coverage.t -> t
end

module Patch : sig
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

  val normalize : Proposed_patch.t -> t
end

module Snapshot : sig
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

  val normalize : Resolution_snapshot.t -> t
end

module Diagnostic : sig
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

  val normalize : semantic_diagnostic -> t
  val compare : t -> t -> int
end

module Conflict : sig
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

  val normalize : semantic_conflict -> t
end

module Capability : sig
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

  val normalize : semantic_capability -> t
end

module Workspace_snapshot : sig
  type file = {
    path : string;
    content_hex : string;
    content_identity : Content_identity.t;
  }

  type t = {
    files : file list;
  }

  val normalize : semantic_workspace_snapshot -> t
end

module Command_result : sig
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

  val normalize : semantic_command_result -> t
end
