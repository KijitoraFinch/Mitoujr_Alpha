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

type t = {
  code : code;
  effective_severity : severity;
  message : string;
  location : location option;
  suggested_fixes : Proposed_patch.t list;
}

let default_severity = function
  | Sidecar_only -> Info
  | Inline_only | Duplicate | Unreferenced_ref | Unsupported_artifact -> Warning
  | Divergent | Stale_selector | Unresolved_ref | Expectation_failed
  | Invalid_sidecar | Invalid_selector ->
      Error

let make ~code ?effective_severity ~message ?location
    ?(suggested_fixes = []) () =
  if String.length message = 0 then
    Result.Error "diagnostic message must not be empty"
  else if
    match location with
    | None -> false
    | Some location ->
        location.artifact = None
        && location.region = None
        && location.annotation = None
        && location.range = None
  then Result.Error "diagnostic location must contain at least one field"
  else
    Result.Ok
      {
        code;
        effective_severity =
          Option.value effective_severity ~default:(default_severity code);
        message;
        location;
        suggested_fixes;
      }

let code value = value.code
let effective_severity value = value.effective_severity
let message value = value.message
let location value = value.location
let suggested_fixes value = value.suggested_fixes

let code_string = function
  | Sidecar_only -> "sidecar-only"
  | Inline_only -> "inline-only"
  | Divergent -> "divergent"
  | Stale_selector -> "stale-selector"
  | Duplicate -> "duplicate"
  | Unreferenced_ref -> "unreferenced-ref"
  | Unresolved_ref -> "unresolved-ref"
  | Expectation_failed -> "expectation-failed"
  | Invalid_sidecar -> "invalid-sidecar"
  | Invalid_selector -> "invalid-selector"
  | Unsupported_artifact -> "unsupported-artifact"

let severity_string = function
  | Info -> "info"
  | Warning -> "warning"
  | Error -> "error"

let compare left right =
  match String.compare (code_string left.code) (code_string right.code) with
  | 0 -> (
      let location_key value =
        Option.bind value.location (fun location -> location.artifact)
        |> Option.map Identifier.to_string
      in
      match Option.compare String.compare (location_key left) (location_key right) with
      | 0 -> String.compare left.message right.message
      | other -> other)
  | other -> other
