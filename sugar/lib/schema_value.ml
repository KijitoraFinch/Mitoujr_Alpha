type t = {
  schema : string;
  value : Normalized_value.t;
}

let make ~schema ~value () =
  if String.length schema = 0 then Error "schema identity must not be empty"
  else if not (Utf8.is_valid schema) then
    Error "schema identity must be valid UTF-8"
  else
    Normalized_value.make value
    |> Result.map (fun value -> { schema; value })

let schema value = value.schema
let value value = value.value

let compare left right =
  match String.compare left.schema right.schema with
  | 0 -> Normalized_value.compare left.value right.value
  | other -> other

let equal left right = compare left right = 0
