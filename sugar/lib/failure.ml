type operation = Observe | Resolve_region

type t = {
  operation : operation;
  code : string;
  message : string;
}

let valid value = String.length value > 0 && Utf8.is_valid value

let make ~operation ~code ~message () =
  if not (valid code) then Error "failure code must be non-empty UTF-8"
  else if not (valid message) then Error "failure message must be non-empty UTF-8"
  else Ok { operation; code; message }

let operation value = value.operation
let code value = value.code
let message value = value.message
let operation_rank = function Observe -> 0 | Resolve_region -> 1

let compare left right =
  match Int.compare (operation_rank left.operation) (operation_rank right.operation) with
  | 0 -> (
      match String.compare left.code right.code with
      | 0 -> String.compare left.message right.message
      | other -> other)
  | other -> other

let equal left right = compare left right = 0
