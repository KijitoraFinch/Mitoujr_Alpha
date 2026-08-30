type target =
  | Address of Region_address.t
  | Unresolved_reference of Reference_id.t

type t = {
  source : Region_address.t;
  target : target;
  source_resolution : Endpoint_resolution.t;
  target_resolution : Endpoint_resolution.t;
  use : Reference_use.t;
}

let make ~source ~target ~source_resolution ~target_resolution ~use =
  { source; target; source_resolution; target_resolution; use }

let source value = value.source
let target value = value.target
let source_resolution value = value.source_resolution
let target_resolution value = value.target_resolution
let use value = value.use

let compare_target left right =
  match left, right with
  | Address left, Address right -> Region_address.compare left right
  | Unresolved_reference left, Unresolved_reference right ->
      Reference_id.compare left right
  | Address _, Unresolved_reference _ -> -1
  | Unresolved_reference _, Address _ -> 1

let compare left right =
  match Region_address.compare left.source right.source with
  | 0 -> (
      match compare_target left.target right.target with
      | 0 -> (
          match Reference_use.compare left.use right.use with
          | 0 -> (
              match
                Endpoint_resolution.compare left.source_resolution
                  right.source_resolution
              with
              | 0 ->
                  Endpoint_resolution.compare left.target_resolution
                    right.target_resolution
              | other -> other)
          | other -> other)
      | other -> other)
  | other -> other
