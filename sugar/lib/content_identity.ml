type t = {
  digest : Content_digest.t;
  byte_length : int;
}

let make ~sha256 ~byte_length =
  match Content_digest.of_hex sha256 with
  | Error _ as error -> error
  | Ok digest ->
      if byte_length < 0 then Error "byte length must not be negative"
      else Ok { digest; byte_length }

let of_content content =
  {
    digest = Content_digest.of_content content;
    byte_length = String.length content;
  }

let sha256 value = Content_digest.to_hex value.digest
let byte_length value = value.byte_length
let display_hash value = Content_digest.to_string value.digest

let compare left right =
  match Content_digest.compare left.digest right.digest with
  | 0 -> Int.compare left.byte_length right.byte_length
  | other -> other

let equal left right = compare left right = 0
