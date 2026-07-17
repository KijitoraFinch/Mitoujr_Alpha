type t = {
  id : Region_id.t;
  selector : Selector.t;
  interpreter : string;
  summary : string option;
  range : Text_range.t option;
  fingerprint : string option;
}

let make ~id ~selector ~interpreter ?summary ?range ?fingerprint () =
  if String.length interpreter = 0 then
    Error "region interpreter must not be empty"
  else if not (Utf8.is_valid interpreter) then
    Error "region interpreter must be valid UTF-8"
  else if Option.fold ~none:false ~some:(Fun.negate Utf8.is_valid) summary then
    Error "region summary must be valid UTF-8"
  else if
    Option.fold ~none:false ~some:(Fun.negate Utf8.is_valid) fingerprint
  then Error "region fingerprint must be valid UTF-8"
  else
    Ok { id; selector; interpreter; summary; range; fingerprint }

let id value = value.id
let artifact value = Region_id.artifact value.id
let selector value = value.selector
let interpreter value = value.interpreter
let summary value = value.summary
let range value = value.range
let fingerprint value = value.fingerprint
