type t = {
  source : string;
  detail : string option;
}

let make ~source ?detail () =
  if String.length source = 0 then Error "provenance source must not be empty"
  else Ok { source; detail }

let source value = value.source
let detail value = value.detail

let compare left right =
  match String.compare left.source right.source with
  | 0 -> Option.compare String.compare left.detail right.detail
  | other -> other
