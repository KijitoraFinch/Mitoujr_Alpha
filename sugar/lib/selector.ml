module Field_name = struct
  type t = string

  let make value =
    if String.length value = 0 then
      Error "row-filter field name must not be empty"
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

type t =
  | Whole_artifact
  | Region_id of Identifier.t
  | Text_range of Text_range.t
  | Row_filter of Row_filter.t

let rank = function
  | Whole_artifact -> 0
  | Region_id _ -> 1
  | Text_range _ -> 2
  | Row_filter _ -> 3

let compare left right =
  match Int.compare (rank left) (rank right) with
  | 0 -> (
      match (left, right) with
      | Whole_artifact, Whole_artifact -> 0
      | Region_id left, Region_id right -> Identifier.compare left right
      | Text_range left, Text_range right -> Text_range.compare left right
      | Row_filter left, Row_filter right -> Row_filter.compare left right
      | _ -> assert false)
  | other -> other
