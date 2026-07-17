type t = {
  source : string;
  detail : string option;
}

let make ~source ?detail () =
  if String.length source = 0 then Error "provenance source must not be empty"
  else if not (Utf8.is_valid source) then
    Error "provenance source must be valid UTF-8"
  else if Option.fold ~none:false ~some:(Fun.negate Utf8.is_valid) detail then
    Error "provenance detail must be valid UTF-8"
  else Ok { source; detail }

let source value = value.source
let detail value = value.detail

let compare left right =
  match String.compare left.source right.source with
  | 0 -> Option.compare String.compare left.detail right.detail
  | other -> other
