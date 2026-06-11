val schema_version : string

type semantic_content_identity = Content_identity.t
type semantic_selector = Selector.t
type semantic_provenance = Provenance.t
type semantic_diagnostic = Diagnostic.t
type semantic_conflict = Conflict.t
type semantic_command_result = Command_result.t
type semantic_workspace_snapshot = Workspace_snapshot.t
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

module Patch : sig
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

  val normalize : Proposed_patch.t -> t
end

module Snapshot : sig
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

  val normalize : Resolution_snapshot.t -> t
end

module Diagnostic : sig
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

  val normalize : semantic_diagnostic -> t
  val compare : t -> t -> int
end

module Conflict : sig
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

  val normalize : semantic_conflict -> t
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

  val normalize : semantic_command_result -> t
end
