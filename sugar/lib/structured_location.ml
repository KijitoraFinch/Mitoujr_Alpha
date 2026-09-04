type t = {
  schema : string;
  value : Normalized_value.t;
}

let make ~schema ~value =
  if String.length schema = 0 then Error "structured location schema must not be empty"
  else if not (Utf8.is_valid schema) then
    Error "structured location schema must be valid UTF-8"
  else
    Normalized_value.make ~path:"$structuredLocation.value" value
    |> Result.map (fun value -> { schema; value })

let schema value = value.schema
let value value = Normalized_value.to_yojson value.value

let compare left right =
  match String.compare left.schema right.schema with
  | 0 -> Normalized_value.compare left.value right.value
  | other -> other
