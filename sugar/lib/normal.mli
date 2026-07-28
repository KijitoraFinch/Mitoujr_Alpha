val schema_version : string

type semantic_content_identity = Content_identity.t
type semantic_selector = Selector.t
type semantic_provenance = Provenance.t
type semantic_diagnostic = Diagnostic.t
type semantic_conflict = Conflict.t
type semantic_command_result = Command_result.t
type semantic_workspace_snapshot = Workspace_snapshot.t
type semantic_artifact = Artifact.t
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
    | Whole_artifact
    | Region_id of string
    | Text_range of Range.t
    | Row_filter of { where : (string * literal) list }

  val normalize : semantic_selector -> t
end

module Origin : sig
  type t =
    | Workspace of string
    | Git of { repo : string; rev : string option; path : string }
    | Web of string
    | Generated of string
    | External of string

  val normalize : Artifact.origin -> t
end

module Provenance : sig
  type t = {
    source : string;
    detail : string option;
  }

  val normalize : semantic_provenance -> t
end

module Artifact : sig
  type t = {
    id : string;
    origin : Origin.t;
    media_type : string option;
    content_identity : Content_identity.t;
  }

  val normalize : semantic_artifact -> t
end

module Scoped_id : sig
  type t = {
    artifact : string;
    local : string;
  }
end

module Region_address : sig
  type t = {
    artifact : Origin.t;
    selector : Selector.t;
    interpreter : string option;
  }
end

module Region_ref : sig
  type t = Resolved of Scoped_id.t | Address of Region_address.t
end

module Region : sig
  type t = {
    id : Scoped_id.t;
    selector : Selector.t;
    interpreter : string;
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
    | Markdown_inline of { artifact : string; range : Range.t }
    | Source_comment of { artifact : string; range : Range.t }
    | Sidecar of { artifact : string; path : string option }
    | Generated_index of { artifact : string }

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
    artifact : Origin.t;
    selector : Selector.t;
    interpreter : string option;
  }

  type t = {
    target : target;
    artifact_identity : Content_identity.t;
    region_fingerprint : string option;
    display : string option;
    observed_at : string;
  }

  val normalize : Resolution_snapshot.t -> t
end

module Diagnostic : sig
  type scoped_id = {
    artifact : string;
    local : string;
  }

  type location = {
    artifact : string option;
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

  val normalize : semantic_diagnostic -> t
  val compare : t -> t -> int
end

module Conflict : sig
  type detail =
    | Missing_artifact
    | Artifact_already_exists of { actual : Content_identity.t }
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
  type changed_artifact = {
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
    changed_artifacts : changed_artifact list;
    conflicts : Conflict.t list;
    snapshots : Snapshot.t list;
    artifacts : Artifact.t list;
    regions : Region.t list;
    references : Reference.t list;
    annotations : Annotation.t list;
    capabilities : Capability.t list;
    summary : (string * summary_value) list option;
    exit_class : string;
  }

  val normalize : semantic_command_result -> t
end
