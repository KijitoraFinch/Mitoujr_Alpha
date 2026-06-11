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

type changed_artifact = {
  path : Workspace_path.t;
  before : Content_identity.t;
  after : Content_identity.t;
}

type t

val make :
  command:string ->
  termination:termination ->
  effect:effect ->
  ?diagnostics:Diagnostic.t list ->
  ?patches:Proposed_patch.t list ->
  ?changed_artifacts:changed_artifact list ->
  ?conflicts:Conflict.t list ->
  ?snapshots:Resolution_snapshot.t list ->
  ?summary:(string * summary_value) list ->
  unit ->
  (t, string) result

val command : t -> string
val termination : t -> termination
val effect : t -> effect
val diagnostics : t -> Diagnostic.t list
val patches : t -> Proposed_patch.t list
val changed_artifacts : t -> changed_artifact list
val conflicts : t -> Conflict.t list
val snapshots : t -> Resolution_snapshot.t list
val summary : t -> (string * summary_value) list option
val status : t -> status
val exit_class : t -> exit_class
val status_string : status -> string
val exit_class_string : exit_class -> string
