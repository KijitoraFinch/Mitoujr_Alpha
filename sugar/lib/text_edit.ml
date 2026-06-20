type t = {
  range : Text_range.t;
  replacement : string;
}

let make ~range ~replacement = { range; replacement }
let range value = value.range
let replacement value = value.replacement

let compare left right =
  match Text_range.compare left.range right.range with
  | 0 -> String.compare left.replacement right.replacement
  | other -> other
