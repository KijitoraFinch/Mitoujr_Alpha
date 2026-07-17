type t = string

let make value =
  if String.length value = 0 then Error "identifier must not be empty"
  else if not (Utf8.is_valid value) then Error "identifier must be valid UTF-8"
  else Ok value

let to_string value = value
let compare = String.compare
let equal = String.equal
