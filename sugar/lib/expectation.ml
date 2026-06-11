type t =
  | Digest of string

let digest value =
  if String.length value = 0 then Error "expectation digest must not be empty"
  else Ok (Digest value)

let compare left right = Stdlib.compare left right
