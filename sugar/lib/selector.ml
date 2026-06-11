type row_filter = {
  where : (string * string) list;
}

type t =
  | Whole_artifact
  | Region_id of Identifier.t
  | Text_range of Text_range.t
  | Row_filter of row_filter

let row_filter ~where =
  let compare_condition (left, _) (right, _) = String.compare left right in
  let where = List.sort compare_condition where in
  let rec validate previous = function
    | [] -> Ok ()
    | (name, _) :: _ when String.length name = 0 ->
        Error "row-filter condition name must not be empty"
    | (name, _) :: _ when Option.equal String.equal previous (Some name) ->
        Error ("duplicate row-filter condition: " ^ name)
    | (name, _) :: rest -> validate (Some name) rest
  in
  match where with
  | [] -> Error "row-filter must contain at least one condition"
  | _ -> (
      match validate None where with
      | Error _ as error -> error
      | Ok () -> Ok { where })

let row_filter_where value = value.where

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
      | Row_filter left, Row_filter right ->
          List.compare
            (fun (left_name, left_value) (right_name, right_value) ->
              match String.compare left_name right_name with
              | 0 -> String.compare left_value right_value
              | other -> other)
            left.where right.where
      | _ -> assert false)
  | other -> other
