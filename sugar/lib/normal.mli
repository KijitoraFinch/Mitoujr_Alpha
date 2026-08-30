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
end

module Region_ref : sig
  type t = Resolved of Scoped_id.t | Address of Region_address.t
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
    id : Scoped_id.t;
    target : Region_address.t;
    binding : string;
    expectations : Expectation.t list;
    provenance : Provenance.t list;
  }

  val normalize : semantic_reference -> t
end

module Annotation : sig
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

  val normalize : semantic_annotation -> t
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
    annotation : scoped_id option;
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
    regions : Region.t list;
    references : Reference.t list;
    annotations : Annotation.t list;
    capabilities : Capability.t list;
    summary : (string * summary_value) list option;
    exit_class : string;
  }

  val normalize : semantic_command_result -> t
end
