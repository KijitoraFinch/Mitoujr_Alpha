type code =
  | Sidecar_only
  | Inline_only
  | Divergent
  | Stale_selector
  | Duplicate
  | Unreferenced_ref
  | Unresolved_ref
  | Expectation_failed
  | Resolution_changed
  | Invalid_sidecar
  | Invalid_selector
  | Authored_override
  | Unsupported_observation
  | Unsupported_filesystem_entry
  | Observation_failure
  | Metadata_failure
  | Extension_failure

type severity = Info | Warning | Error

type location = {
  observation : Observation_id.t option;
  region : Region_id.t option;
  annotation : Annotation_id.t option;
  range : Text_range.t option;
}

type t = {
  code : code;
  effective_severity : severity;
  message : string;
  location : location option;
  extension_failure : Extension_failure.t option;
  suggested_fixes : Proposed_patch.t list;
}

let default_severity = function
  | Sidecar_only | Authored_override -> Info
  | Inline_only | Duplicate | Unreferenced_ref | Resolution_changed
  | Unsupported_observation | Unsupported_filesystem_entry ->
      Warning
  | Divergent | Stale_selector | Unresolved_ref | Expectation_failed
  | Invalid_sidecar | Invalid_selector | Observation_failure | Metadata_failure
  | Extension_failure ->
      Error

let make ~code ?effective_severity ~message ?location ?extension_failure
    ?(suggested_fixes = []) () =
  if String.length message = 0 then
    Result.Error "diagnostic message must not be empty"
  else if not (Utf8.is_valid message) then
    Result.Error "diagnostic message must be valid UTF-8"
  else if
    match location with
    | None -> false
    | Some location ->
        location.observation = None
        && location.region = None
        && location.annotation = None
        && location.range = None
  then Result.Error "diagnostic location must contain at least one field"
  else if
    match location with
    | None -> false
    | Some location ->
        let scoped_observations =
          Option.to_list (Option.map Region_id.observation location.region)
        in
        let observations =
          Option.to_list location.observation @ scoped_observations
        in
        (match observations with
        | [] | [ _ ] -> false
        | first :: rest ->
            List.exists (Fun.negate (Observation_id.equal first)) rest)
  then Result.Error "diagnostic location scopes must refer to one observation"
  else if
    match (code, extension_failure) with
    | Extension_failure, None -> true
    | ( Unsupported_observation | Unresolved_ref | Invalid_selector
      | Extension_failure ),
      Some failure ->
        not (String.equal message (Extension_failure.message failure))
    | _, Some _ -> true
    | _, None -> false
  then
    Result.Error
      "extension failure details must match an extension-related diagnostic"
  else
    Result.Ok
      {
        code;
        effective_severity =
          Option.value effective_severity ~default:(default_severity code);
        message;
        location;
        extension_failure;
        suggested_fixes;
      }

let code value = value.code
let effective_severity value = value.effective_severity
let message value = value.message
let location value = value.location
let extension_failure value = value.extension_failure
let suggested_fixes value = value.suggested_fixes
let with_effective_severity effective_severity value =
  { value with effective_severity }

let code_string = function
  | Sidecar_only -> "sidecar-only"
  | Inline_only -> "inline-only"
  | Divergent -> "divergent"
  | Stale_selector -> "stale-selector"
  | Duplicate -> "duplicate"
  | Unreferenced_ref -> "unreferenced-ref"
  | Unresolved_ref -> "unresolved-ref"
  | Expectation_failed -> "expectation-failed"
  | Resolution_changed -> "resolution-changed"
  | Invalid_sidecar -> "invalid-sidecar"
  | Invalid_selector -> "invalid-selector"
  | Authored_override -> "authored-override"
  | Unsupported_observation -> "unsupported-observation"
  | Unsupported_filesystem_entry -> "unsupported-filesystem-entry"
  | Observation_failure -> "observation-failure"
  | Metadata_failure -> "metadata-failure"
  | Extension_failure -> "extension-failure"

let severity_string = function
  | Info -> "info"
  | Warning -> "warning"
  | Error -> "error"

let code_of_string = function
  | "sidecar-only" -> Ok Sidecar_only
  | "inline-only" -> Ok Inline_only
  | "divergent" -> Ok Divergent
  | "stale-selector" -> Ok Stale_selector
  | "duplicate" -> Ok Duplicate
  | "unreferenced-ref" -> Ok Unreferenced_ref
  | "unresolved-ref" -> Ok Unresolved_ref
  | "expectation-failed" -> Ok Expectation_failed
  | "resolution-changed" -> Ok Resolution_changed
  | "invalid-sidecar" -> Ok Invalid_sidecar
  | "invalid-selector" -> Ok Invalid_selector
  | "authored-override" -> Ok Authored_override
  | "unsupported-observation" -> Ok Unsupported_observation
  | "unsupported-filesystem-entry" -> Ok Unsupported_filesystem_entry
  | "observation-failure" -> Ok Observation_failure
  | "metadata-failure" -> Ok Metadata_failure
  | "extension-failure" -> Ok Extension_failure
  | value -> Error ("unsupported diagnostic code: " ^ value)

let severity_of_string = function
  | "info" -> Ok Info
  | "warning" -> Ok Warning
  | "error" -> Ok Error
  | value -> Error ("unsupported diagnostic severity: " ^ value)

let compare left right =
  match String.compare (code_string left.code) (code_string right.code) with
  | 0 -> (
      let location_key value =
        Option.bind value.location (fun location -> location.observation)
        |> Option.map Observation_id.to_string
      in
      match Option.compare String.compare (location_key left) (location_key right) with
      | 0 -> (
          match String.compare left.message right.message with
          | 0 ->
              Option.compare Extension_failure.compare left.extension_failure
                right.extension_failure
          | other -> other)
      | other -> other)
  | other -> other
