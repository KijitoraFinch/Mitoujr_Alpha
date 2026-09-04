type t = {
  name : string;
  version : string;
}

let nonempty name value =
  if String.length value = 0 then Error (name ^ " must not be empty")
  else if not (Utf8.is_valid value) then Error (name ^ " must be valid UTF-8")
  else Ok value

let make ~name ~version () =
  match
    ( nonempty "resource observer name" name,
      nonempty "resource observer version" version )
  with
  | Ok name, Ok version -> Ok { name; version }
  | (Error _ as error), _ | _, (Error _ as error) -> error

let name value = value.name
let version value = value.version

let compare left right =
  match String.compare left.name right.name with
  | 0 -> String.compare left.version right.version
  | other -> other

let equal left right = compare left right = 0
