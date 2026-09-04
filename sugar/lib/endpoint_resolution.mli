type t =
  | Resolved
  | Unresolved
  | Invalid_selector
  | Unreadable
  | Not_checked

val compare : t -> t -> int
