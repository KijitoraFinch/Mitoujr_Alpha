type t =
  | Digest of Content_digest.t

val compare : t -> t -> int
