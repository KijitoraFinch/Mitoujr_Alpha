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
    value : Yojson.Safe.t;
    canonical : string;
  }

  let duplicate_name fields =
    let names = List.map fst fields |> List.sort String.compare in
    let rec loop = function
      | left :: (right :: _ as rest) ->
          String.equal left right || loop rest
      | [] | [ _ ] -> false
    in
    loop names

  let rec normalize path = function
    | `Null -> Ok `Null
    | `Bool value -> Ok (`Bool value)
    | `String value when Utf8.is_valid value -> Ok (`String value)
    | `String _ -> Error (path ^ ": string must be valid UTF-8")
    | `Int value when Protocol_integer.is_safe value -> Ok (`Int value)
    | `Int _ -> Error (path ^ ": integer exceeds the protocol safe range")
    | `Intlit value -> (
        match int_of_string_opt value with
        | Some value when Protocol_integer.is_safe value -> Ok (`Int value)
        | _ -> Error (path ^ ": integer exceeds the protocol safe range"))
    | `List values ->
        values
        |> List.mapi (fun index value ->
               normalize (Printf.sprintf "%s[%d]" path index) value)
        |> List.fold_left
             (fun result item ->
               Result.bind result (fun values ->
                   Result.map (fun value -> value :: values) item))
             (Ok [])
        |> Result.map List.rev |> Result.map (fun values -> `List values)
    | `Assoc fields ->
        if List.exists (fun (name, _) -> not (Utf8.is_valid name)) fields then
          Error (path ^ ": object field must be valid UTF-8")
        else if duplicate_name fields then
          Error (path ^ ": object fields must be unique")
        else
          fields
          |> List.sort (fun (left, _) (right, _) -> String.compare left right)
          |> List.fold_left
               (fun result (name, value) ->
                 Result.bind result (fun fields ->
                     Result.map
                       (fun value -> (name, value) :: fields)
                       (normalize (path ^ "." ^ name) value)))
               (Ok [])
          |> Result.map List.rev |> Result.map (fun fields -> `Assoc fields)
    | `Float _ -> Error (path ^ ": floating-point values are not supported")
    | `Tuple _ | `Variant _ -> Error (path ^ ": value must be valid JSON")

  let make ~schema ~value =
    if String.length schema = 0 then
      Error "extension selector schema must not be empty"
    else if not (Utf8.is_valid schema) then
      Error "extension selector schema must be valid UTF-8"
    else
      Result.map
        (fun value ->
          { schema; canonical = Yojson.Safe.to_string value; value })
        (normalize "$selector.value" value)

  let schema value = value.schema
  let value value = value.value

  let compare left right =
    match String.compare left.schema right.schema with
    | 0 -> String.compare left.canonical right.canonical
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
