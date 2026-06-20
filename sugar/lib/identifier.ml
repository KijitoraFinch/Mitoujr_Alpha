type t = string

let make value =
  if String.length value = 0 then Error "identifier must not be empty"
  else Ok value

let to_string value = value
let compare = String.compare
let equal = String.equal
