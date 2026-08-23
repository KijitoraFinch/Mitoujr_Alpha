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

type t = {
  command : string;
  termination : termination;
  effect : effect;
  diagnostics : Diagnostic.t list;
  patches : Proposed_patch.t list;
  changed_files : changed_file list;
  conflicts : Conflict.t list;
  snapshots : Resolution_snapshot.t list;
  observations : Observation.t list;
  regions : Region.t list;
  references : Reference.t list;
  annotations : Annotation.t list;
  capabilities : Capability.t list;
  summary : (string * summary_value) list option;
}

let has_duplicate compare values =
  let sorted = List.sort compare values in
  let rec loop = function
    | left :: (right :: _ as rest) ->
        compare left right = 0 || loop rest
    | _ -> false
  in
  loop sorted

let region_refs annotation =
  let subject =
    match Annotation.subject annotation with Annotation.Region value -> [ value ]
  in
  match Annotation.object_ annotation with
  | Annotation.Region_object value -> value :: subject
  | Annotation.Reference_object _ | Annotation.Literal _ -> subject

let validate_observations ~observations ~regions ~references ~annotations =
  let observation_ids = List.map Observation.id observations in
  let region_ids = List.map Region.id regions in
  let reference_ids = List.map Reference.id references in
  let annotation_ids = List.map Annotation.id annotations in
  let known_observation id = List.exists (Observation_id.equal id) observation_ids in
  let matching_region_identity region =
    match
      List.find_opt
        (fun observation ->
          Observation_id.equal (Observation.id observation) (Region.observation region))
        observations
    with
    | None -> false
    | Some observation ->
        Observation_identity.equal
          (Observation.identity observation)
          (Region.observation_identity region)
  in
  let known_region id = List.exists (Region_id.equal id) region_ids in
  let known_reference id =
    List.exists (Reference_id.equal id) reference_ids
  in
  if has_duplicate Observation_id.compare observation_ids then
    Error "observation IDs must be unique"
  else if has_duplicate Region_id.compare region_ids then
    Error "region IDs must be unique"
  else if has_duplicate Reference_id.compare reference_ids then
    Error "reference IDs must be unique"
  else if has_duplicate Annotation_id.compare annotation_ids then
    Error "annotation IDs must be unique"
  else if
    List.exists
      (fun id -> not (known_observation (Region_id.observation id)))
      region_ids
  then Error "region parent observation must be present"
  else if List.exists (Fun.negate matching_region_identity) regions then
    Error "region must belong to the observation"
  else if
    List.exists
      (fun id -> not (known_observation (Reference_id.observation id)))
      reference_ids
  then Error "reference parent observation must be present"
  else if
    List.exists
      (fun id -> not (known_observation (Annotation_id.observation id)))
      annotation_ids
  then Error "annotation parent observation must be present"
  else if
    List.exists
      (fun annotation ->
        List.exists
          (function
            | Region_ref.Resolved id -> not (known_region id)
            | Region_ref.Address _ -> false)
          (region_refs annotation))
      annotations
  then Error "resolved annotation region must be present"
  else if
    List.exists
      (fun annotation ->
        match Annotation.object_ annotation with
        | Annotation.Reference_object id -> not (known_reference id)
        | Annotation.Region_object _ | Annotation.Literal _ -> false)
      annotations
  then Error "annotation reference object must be present"
  else Ok ()

let make ~command ~termination ~effect ?(diagnostics = []) ?(patches = [])
    ?(changed_files = []) ?(conflicts = []) ?(snapshots = [])
    ?(observations = []) ?(regions = []) ?(references = []) ?(annotations = [])
    ?(capabilities = []) ?summary () =
  let require_empty name values =
    if values = [] then Stdlib.Ok ()
    else Error (name ^ " must be empty for this effect")
  in
  let require_nonempty name values =
    if values = [] then Error (name ^ " must not be empty for this effect")
    else Stdlib.Ok ()
  in
  let validate_effect_payload () =
    match effect with
    | No_change -> (
        match require_empty "patches" patches with
        | Error _ as error -> error
        | Stdlib.Ok () -> (
            match require_empty "changed files" changed_files with
            | Error _ as error -> error
            | Stdlib.Ok () -> require_empty "conflicts" conflicts))
    | Patches_proposed -> (
        match require_nonempty "patches" patches with
        | Error _ as error -> error
        | Stdlib.Ok () -> (
            match require_empty "changed files" changed_files with
            | Error _ as error -> error
            | Stdlib.Ok () -> require_empty "conflicts" conflicts))
    | Applied -> (
        match require_nonempty "changed files" changed_files with
        | Error _ as error -> error
        | Stdlib.Ok () -> (
            match require_empty "patches" patches with
            | Error _ as error -> error
            | Stdlib.Ok () -> require_empty "conflicts" conflicts))
    | Conflicted -> (
        match require_nonempty "conflicts" conflicts with
        | Error _ as error -> error
        | Stdlib.Ok () -> (
            match require_empty "patches" patches with
            | Error _ as error -> error
            | Stdlib.Ok () -> require_empty "changed files" changed_files))
  in
  if String.length command = 0 then Error "command must not be empty"
  else if not (Utf8.is_valid command) then Error "command must be valid UTF-8"
  else if
    match termination with
    | Completed -> false
    | Usage_failure message | Internal_failure message ->
        not (Utf8.is_valid message)
  then Error "termination message must be valid UTF-8"
  else if
    match summary with
    | None -> false
    | Some entries ->
        List.exists
          (fun (name, value) ->
            not (Utf8.is_valid name)
            ||
            match value with
            | Text text -> not (Utf8.is_valid text)
            | Count _ | Flag _ -> false)
          entries
  then Error "summary keys and text values must be valid UTF-8"
  else if termination <> Completed && effect <> No_change then
    Error "failed termination must not report a workspace effect"
  else if
    match summary with
    | None -> false
    | Some entries ->
        List.exists
          (function
            | _, Count value ->
                not (Protocol_integer.is_nonnegative_safe value)
            | _ -> false)
          entries
  then Error "summary count must be a non-negative protocol safe integer"
  else
    match validate_observations ~observations ~regions ~references ~annotations with
    | Error _ as error -> error
    | Ok () when has_duplicate Capability.compare capabilities ->
        Error "capability observations must be unique"
    | Ok ()
      when has_duplicate Patch_id.compare
             (List.map Proposed_patch.id patches) ->
        Error "patch IDs must be unique"
    | Ok () ->
    match validate_effect_payload () with
    | Error _ as error -> error
    | Stdlib.Ok () ->
        if
          match summary with
          | None -> false
          | Some entries ->
              let names = List.map fst entries |> List.sort String.compare in
              let rec has_duplicate = function
                | left :: (right :: _ as rest) ->
                    String.equal left right || has_duplicate rest
                | _ -> false
              in
              has_duplicate names
        then Error "summary keys must be unique"
        else
          Stdlib.Ok
            {
              command;
              termination;
              effect;
              diagnostics;
              patches;
              changed_files;
              conflicts;
              snapshots;
              observations;
              regions;
              references;
              annotations;
              capabilities;
              summary;
            }

let internal_error ~command ~error_code ~operation =
  {
    command;
    termination = Internal_failure "internal operation failed";
    effect = No_change;
    diagnostics = [];
    patches = [];
    changed_files = [];
    conflicts = [];
    snapshots = [];
    observations = [];
    regions = [];
    references = [];
    annotations = [];
    capabilities = [];
    summary =
      Some
        [
          ("errorCode", Text error_code);
          ("operation", Text operation);
        ];
  }

let command value = value.command
let termination value = value.termination
let effect value = value.effect
let diagnostics value = value.diagnostics
let patches value = value.patches
let changed_files value = value.changed_files
let conflicts value = value.conflicts
let snapshots value = value.snapshots
let observations value = value.observations
let regions value = value.regions
let references value = value.references
let annotations value = value.annotations
let capabilities value = value.capabilities
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
