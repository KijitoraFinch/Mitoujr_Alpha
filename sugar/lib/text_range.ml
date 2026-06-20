type t = {
  start : int;
  end_ : int;
}

let make ~start ~end_ =
  if start < 0 then Error "range start must not be negative"
  else if end_ < start then Error "range end must not precede start"
  else Ok { start; end_ }

let start value = value.start
let end_ value = value.end_
let length value = value.end_ - value.start

let compare left right =
  match Int.compare left.start right.start with
  | 0 -> Int.compare left.end_ right.end_
  | other -> other
