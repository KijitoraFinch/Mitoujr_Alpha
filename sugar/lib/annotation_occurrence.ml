type t = {
  annotation : Annotation.t;
  source : Source_location.t;
}

let make ~annotation ~source = { annotation; source }
let annotation value = value.annotation
let source value = value.source

let compare left right =
  match Annotation.compare left.annotation right.annotation with
  | 0 -> Source_location.compare left.source right.source
  | other -> other
