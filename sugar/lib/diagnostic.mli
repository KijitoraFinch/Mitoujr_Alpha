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
  | Unsupported_artifact

type severity = Info | Warning | Error

type location = {
  artifact : Identifier.t option;
  region : Identifier.t option;
  annotation : Identifier.t option;
  range : Text_range.t option;
}

type t

val make :
  code:code ->
  ?effective_severity:severity ->
  message:string ->
  ?location:location ->
  ?suggested_fixes:Proposed_patch.t list ->
  unit ->
  (t, string) result

val default_severity : code -> severity
val code : t -> code
val effective_severity : t -> severity
val message : t -> string
val location : t -> location option
val suggested_fixes : t -> Proposed_patch.t list
val code_string : code -> string
val severity_string : severity -> string
val compare : t -> t -> int
