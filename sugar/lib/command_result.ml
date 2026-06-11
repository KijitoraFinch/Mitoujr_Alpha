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

type t = {
  command : string;
  termination : termination;
  effect : effect;
  diagnostics : Diagnostic.t list;
  patches : Proposed_patch.t list;
  changed_artifacts : changed_artifact list;
  conflicts : Conflict.t list;
  snapshots : Resolution_snapshot.t list;
  summary : (string * summary_value) list option;
}

let make ~command ~termination ~effect ?(diagnostics = []) ?(patches = [])
    ?(changed_artifacts = []) ?(conflicts = []) ?(snapshots = []) ?summary () =
  if String.length command = 0 then Error "command must not be empty"
  else
    Ok
      {
        command;
        termination;
        effect;
        diagnostics;
        patches;
        changed_artifacts;
        conflicts;
        snapshots;
        summary;
      }

let command value = value.command
let termination value = value.termination
let effect value = value.effect
let diagnostics value = value.diagnostics
let patches value = value.patches
let changed_artifacts value = value.changed_artifacts
let conflicts value = value.conflicts
let snapshots value = value.snapshots
let summary value = value.summary

let status value =
  match value.termination with
  | Usage_failure _ -> Invalid_input
  | Internal_failure _ -> Internal_error
  | Completed -> (
      match value.effect with
      | Conflicted -> Conflict_status
      | Applied -> Applied_status
      | Patches_proposed -> Patches_proposed_status
      | No_change ->
          if value.diagnostics = [] then Ok else Diagnostics_found)

let has_error diagnostics =
  List.exists
    (fun diagnostic ->
      Diagnostic.effective_severity diagnostic = Diagnostic.Error)
    diagnostics

let exit_class value =
  match value.termination with
  | Usage_failure _ -> Usage_error
  | Internal_failure _ -> Internal_error_exit
  | Completed ->
      if value.effect = Conflicted || has_error value.diagnostics then
        Diagnostic_error
      else Success

let status_string = function
  | Ok -> "ok"
  | Diagnostics_found -> "diagnostics-found"
  | Patches_proposed_status -> "patches-proposed"
  | Applied_status -> "applied"
  | Conflict_status -> "conflict"
  | Invalid_input -> "invalid-input"
  | Internal_error -> "internal-error"

let exit_class_string = function
  | Success -> "success"
  | Diagnostic_error -> "diagnostic-error"
  | Usage_error -> "usage-error"
  | Internal_error_exit -> "internal-error"
