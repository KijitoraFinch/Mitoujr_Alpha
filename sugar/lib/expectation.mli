type t = private
  | Digest of string

val digest : string -> (t, string) result
val compare : t -> t -> int
