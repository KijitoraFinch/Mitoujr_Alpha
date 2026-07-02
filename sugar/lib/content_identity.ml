type t = {
  digest : Content_digest.t;
  byte_length : int;
}

let make ~digest ~byte_length =
  if byte_length < 0 then Error "byte length must not be negative"
  else Ok { digest; byte_length }

let of_sha256_hex ~sha256_hex ~byte_length =
  match Content_digest.of_hex sha256_hex with
  | Error _ as error -> error
  | Ok digest -> make ~digest ~byte_length

let of_display_hash ~hash ~byte_length =
  let prefix = "sha256:" in
  let prefix_length = String.length prefix in
  if
    String.length hash <= prefix_length
    || not (String.equal (String.sub hash 0 prefix_length) prefix)
  then Error "content identity hash must start with sha256:"
  else
    let sha256_hex =
      String.sub hash prefix_length (String.length hash - prefix_length)
    in
    of_sha256_hex ~sha256_hex ~byte_length

let of_content content =
  {
    digest = Content_digest.of_content content;
    byte_length = String.length content;
  }

let sha256_hex value = Content_digest.to_hex value.digest
let byte_length value = value.byte_length
let display_hash value = Content_digest.to_string value.digest

let compare left right =
  match Content_digest.compare left.digest right.digest with
  | 0 -> Int.compare left.byte_length right.byte_length
  | other -> other

let equal left right = compare left right = 0
