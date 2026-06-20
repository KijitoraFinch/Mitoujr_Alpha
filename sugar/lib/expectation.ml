type t =
  | Digest of Content_digest.t

let compare (Digest left) (Digest right) =
  Content_digest.compare left right
