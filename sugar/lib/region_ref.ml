type t = Resolved of Region_id.t | Address of Region_address.t

let compare left right =
  match (left, right) with
  | Resolved left, Resolved right -> Region_id.compare left right
  | Resolved _, Address _ -> -1
  | Address _, Resolved _ -> 1
  | Address left, Address right -> Region_address.compare left right
