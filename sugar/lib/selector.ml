type row_filter = {
  column : string;
  equals : string;
}

type t =
  | Whole_artifact
  | Region_id of Identifier.t
  | Text_range of Text_range.t
  | Row_filter of row_filter

let row_filter ~column ~equals =
  if String.length column = 0 then Error "row-filter column must not be empty"
  else Ok { column; equals }

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
      | Row_filter left, Row_filter right -> (
          match String.compare left.column right.column with
          | 0 -> String.compare left.equals right.equals
          | other -> other)
      | _ -> assert false)
  | other -> other
