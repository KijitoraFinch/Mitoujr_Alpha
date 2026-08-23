type t = {
  name : string;
  version : string;
}

let valid value = String.length value > 0 && Utf8.is_valid value

let make ~name ~version () =
  if not (valid name) then
    Error "observation type name must be non-empty UTF-8"
  else if not (valid version) then
    Error "observation type version must be non-empty UTF-8"
  else Ok { name; version }

let binary = { name = "application/octet-stream"; version = "1" }
let markdown = { name = "text/markdown"; version = "1" }
let yaml = { name = "application/yaml"; version = "1" }
let jsonl = { name = "application/x-ndjson"; version = "1" }
let name value = value.name
let version value = value.version

let compare left right =
  match String.compare left.name right.name with
  | 0 -> String.compare left.version right.version
  | other -> other

let equal left right = compare left right = 0
