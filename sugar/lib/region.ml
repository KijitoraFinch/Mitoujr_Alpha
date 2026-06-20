type t = {
  id : Identifier.t;
  artifact : Identifier.t;
  selector : Selector.t;
  interpreter : string;
  summary : string option;
  range : Text_range.t option;
  fingerprint : string option;
}

let make ~id ~artifact ~selector ~interpreter ?summary ?range ?fingerprint () =
  if String.length interpreter = 0 then
    Error "region interpreter must not be empty"
  else
    Ok { id; artifact; selector; interpreter; summary; range; fingerprint }

let id value = value.id
let artifact value = value.artifact
let selector value = value.selector
let interpreter value = value.interpreter
let summary value = value.summary
let range value = value.range
let fingerprint value = value.fingerprint
