module Field_name = struct
  type t = string

  let make value =
    if String.length value = 0 then
      Error "row-filter field name must not be empty"
    else if not (Utf8.is_valid value) then
      Error "row-filter field name must be valid UTF-8"
    else Ok value

  let to_string value = value
  let compare = String.compare
end

module Literal = struct
  type t =
    | String of string
    | Int of int
    | Bool of bool

  let compare left right = Stdlib.compare left right
end

module Field_map = Map.Make (Field_name)

module Row_filter = struct
  type t = Literal.t Field_map.t

  let make conditions =
    let rec build condition_map = function
      | [] -> Ok condition_map
      | (field, literal) :: rest ->
          if Field_map.mem field condition_map then
            Error
              ("duplicate row-filter field: " ^ Field_name.to_string field)
          else
            build (Field_map.add field literal condition_map) rest
    in
    match conditions with
    | [] -> Error "row-filter must contain at least one condition"
    | _
      when List.exists
             (function
               | _, Literal.Int value -> not (Protocol_integer.is_safe value)
               | _ -> false)
             conditions ->
        Error "row-filter integer exceeds the protocol safe-integer range"
    | _
      when List.exists
             (function
               | _, Literal.String value -> not (Utf8.is_valid value)
               | _ -> false)
             conditions ->
        Error "row-filter string must be valid UTF-8"
    | _ -> build Field_map.empty conditions

  let conditions = Field_map.bindings

  let compare left right =
    List.compare
      (fun (left_field, left_literal) (right_field, right_literal) ->
        match Field_name.compare left_field right_field with
        | 0 -> Literal.compare left_literal right_literal
        | other -> other)
      (conditions left) (conditions right)
end

module Extension = struct
  type t = {
    schema : string;
    value : Normalized_value.t;
  }

  let make ~schema ~value =
    if String.length schema = 0 then
      Error "extension selector schema must not be empty"
    else if not (Utf8.is_valid schema) then
      Error "extension selector schema must be valid UTF-8"
    else
      Result.map
        (fun value -> { schema; value })
        (Normalized_value.make ~path:"$selector.value" value)

  let schema value = value.schema
  let value value = Normalized_value.to_yojson value.value

  let compare left right =
    match String.compare left.schema right.schema with
    | 0 -> Normalized_value.compare left.value right.value
    | other -> other
end

type t =
  | Whole_observation
  | Region_id of Identifier.t
  | Text_range of Text_range.t
  | Row_filter of Row_filter.t
  | Extension of Extension.t

let extension ~schema ~value =
  Result.map (fun value -> Extension value) (Extension.make ~schema ~value)

let rank = function
  | Whole_observation -> 0
  | Region_id _ -> 1
  | Text_range _ -> 2
  | Row_filter _ -> 3
  | Extension _ -> 4

let compare left right =
  match (left, right) with
  | Whole_observation, Whole_observation -> 0
  | Region_id left, Region_id right -> Identifier.compare left right
  | Text_range left, Text_range right -> Text_range.compare left right
  | Row_filter left, Row_filter right -> Row_filter.compare left right
  | Extension left, Extension right -> Extension.compare left right
  | _ -> Int.compare (rank left) (rank right)
