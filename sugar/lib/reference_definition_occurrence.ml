type t = {
  reference : Reference.t;
  source : Source_location.t;
}

let make ~reference ~source = { reference; source }
let reference value = value.reference
let source value = value.source

let compare left right =
  match Reference.compare left.reference right.reference with
  | 0 -> Source_location.compare left.source right.source
  | other -> other
