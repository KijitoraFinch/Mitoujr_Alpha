type t =
  | Resolved
  | Unresolved
  | Invalid_selector
  | Unreadable
  | Not_checked

let rank = function
  | Resolved -> 0
  | Unresolved -> 1
  | Invalid_selector -> 2
  | Unreadable -> 3
  | Not_checked -> 4

let compare left right = Int.compare (rank left) (rank right)
