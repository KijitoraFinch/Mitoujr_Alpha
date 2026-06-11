type t = {
  sha256 : string;
  byte_length : int;
}

let is_lower_hex = function
  | '0' .. '9' | 'a' .. 'f' -> true
  | _ -> false

let make ~sha256 ~byte_length =
  if String.length sha256 <> 64 || not (String.for_all is_lower_hex sha256) then
    Error "SHA-256 must be 64 lowercase hexadecimal characters"
  else if byte_length < 0 then Error "byte length must not be negative"
  else Ok { sha256; byte_length }

let of_content content =
  {
    sha256 = Digestif.SHA256.(digest_string content |> to_hex);
    byte_length = String.length content;
  }

let sha256 value = value.sha256
let byte_length value = value.byte_length
let display_hash value = "sha256:" ^ value.sha256

let compare left right =
  match String.compare left.sha256 right.sha256 with
  | 0 -> Int.compare left.byte_length right.byte_length
  | other -> other

let equal left right = compare left right = 0
