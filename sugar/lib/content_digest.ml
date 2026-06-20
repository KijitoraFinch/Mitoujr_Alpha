type t = string

let is_lower_hex = function
  | '0' .. '9' | 'a' .. 'f' -> true
  | _ -> false

let of_hex hex =
  if String.length hex <> 64 || not (String.for_all is_lower_hex hex) then
    Error "SHA-256 must be 64 lowercase hexadecimal characters"
  else Ok hex

let of_content content =
  Digestif.SHA256.(digest_string content |> to_hex)

let to_hex value = value
let to_string value = "sha256:" ^ value
let compare = String.compare

let equal left right = compare left right = 0
