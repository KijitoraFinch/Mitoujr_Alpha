type code =
  | Sidecar_only
  | Inline_only
  | Divergent
  | Stale_selector
  | Duplicate
  | Unreferenced_ref
  | Unresolved_ref
  | Expectation_failed
  | Invalid_sidecar
  | Invalid_selector
  | Authored_override
  | Unsupported_observation
  | Unsupported_filesystem_entry
  | Extension_failure

type severity = Info | Warning | Error

type location = {
  observation : Observation_id.t option;
  region : Region_id.t option;
  annotation : Annotation_id.t option;
  range : Text_range.t option;
}

type t

val make :
  code:code ->
  ?effective_severity:severity ->
  message:string ->
  ?location:location ->
  ?extension_failure:Extension_failure.t ->
  ?suggested_fixes:Proposed_patch.t list ->
  unit ->
  (t, string) result

val default_severity : code -> severity
val code : t -> code
val effective_severity : t -> severity
val message : t -> string
val location : t -> location option
val extension_failure : t -> Extension_failure.t option
val suggested_fixes : t -> Proposed_patch.t list
val code_string : code -> string
val severity_string : severity -> string
val compare : t -> t -> int
