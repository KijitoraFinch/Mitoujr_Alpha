type t = {
  name : string;
  version : string;
}

let make ~name ~version =
  if String.length name = 0 then Error "observation encoding name must not be empty"
  else if String.length version = 0 then
    Error "observation encoding version must not be empty"
  else if not (Utf8.is_valid name && Utf8.is_valid version) then
    Error "observation encoding identity must be valid UTF-8"
  else Ok { name; version }

let name value = value.name
let version value = value.version

let compare left right =
  match String.compare left.name right.name with
  | 0 -> String.compare left.version right.version
  | other -> other
