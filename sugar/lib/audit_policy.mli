type sidecar_only = Allow | Report
type t

val make :
  sidecar_only:sidecar_only ->
  severity_overrides:(Diagnostic.code * Diagnostic.severity) list ->
  (t, string) result

val default : t
val sidecar_only : t -> sidecar_only
val severity_overrides : t -> (Diagnostic.code * Diagnostic.severity) list
val severity_for : t -> Diagnostic.code -> Diagnostic.severity
val apply_to_diagnostic : t -> Diagnostic.t -> Diagnostic.t option
val apply : t -> Diagnostic.t list -> Diagnostic.t list
val compare : t -> t -> int
