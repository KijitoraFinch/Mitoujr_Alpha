type termination = Completed | Usage_failure of string | Internal_failure of string
type effect = No_change | Patches_proposed | Applied | Conflicted

type status =
  | Ok
  | Diagnostics_found
  | Patches_proposed_status
  | Applied_status
  | Conflict_status
  | Invalid_input
  | Internal_error

type exit_class = Success | Diagnostic_error | Usage_error | Internal_error_exit
type summary_value = Count of int | Text of string | Flag of bool

type changed_file = {
  path : Workspace_path.t;
  before : Content_identity.t option;
  after : Content_identity.t;
}

type t

val make :
  command:string ->
  termination:termination ->
  effect:effect ->
  ?diagnostics:Diagnostic.t list ->
  ?patches:Proposed_patch.t list ->
  ?changed_files:changed_file list ->
  ?conflicts:Conflict.t list ->
  ?snapshots:Resolution_snapshot.t list ->
  ?observations:Observation.t list ->
  ?sidecar_snapshots:Sidecar_snapshot.t list ->
  ?regions:Region.t list ->
  ?references:Reference.t list ->
  ?annotations:Annotation.t list ->
  ?reference_definitions:Reference_definition_occurrence.t list ->
  ?reference_uses:Reference_use.t list ->
  ?annotation_occurrences:Annotation_occurrence.t list ->
  ?capabilities:Capability.t list ->
  ?coverage:Coverage.t ->
  ?summary:(string * summary_value) list ->
  unit ->
  (t, string) result

(** [internal_error ~command ~error_code ~operation] is a total, payload-free
    internal failure result for a failure that prevented construction of the
    intended command result. Callers should use stable UTF-8 literals for all
    three fields. *)
val internal_error : command:string -> error_code:string -> operation:string -> t

val command : t -> string
val termination : t -> termination
val effect : t -> effect
val diagnostics : t -> Diagnostic.t list
val patches : t -> Proposed_patch.t list
val changed_files : t -> changed_file list
val conflicts : t -> Conflict.t list
val snapshots : t -> Resolution_snapshot.t list
val observations : t -> Observation.t list
val sidecar_snapshots : t -> Sidecar_snapshot.t list
val regions : t -> Region.t list
val references : t -> Reference.t list
val annotations : t -> Annotation.t list
val reference_definitions : t -> Reference_definition_occurrence.t list
val reference_uses : t -> Reference_use.t list
val annotation_occurrences : t -> Annotation_occurrence.t list
val capabilities : t -> Capability.t list
val coverage : t -> Coverage.t
val summary : t -> (string * summary_value) list option
val status : t -> status
val exit_class : t -> exit_class
val status_string : status -> string
val exit_class_string : exit_class -> string
