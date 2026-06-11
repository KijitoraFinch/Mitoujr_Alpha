type row_filter = {
  column : string;
  equals : string;
}

type t =
  | Whole_artifact
  | Region_id of Identifier.t
  | Text_range of Text_range.t
  | Row_filter of row_filter

val row_filter : column:string -> equals:string -> (row_filter, string) result
val compare : t -> t -> int
