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

module Incremental = struct
  type state = Digestif.SHA256.ctx

  let empty () = Digestif.SHA256.init ()

  let feed_bytes state bytes ~offset ~length =
    if offset < 0 || length < 0 || offset > Bytes.length bytes - length then
      invalid_arg "Content_digest.Incremental.feed_bytes"
    else Digestif.SHA256.feed_bytes state bytes ~off:offset ~len:length

  let finish state = Digestif.SHA256.(get state |> to_hex)
end

let to_hex value = value
let to_string value = "sha256:" ^ value
let compare = String.compare

let equal left right = compare left right = 0
