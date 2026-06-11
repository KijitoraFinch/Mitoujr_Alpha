type row_filter

type t =
  | Whole_artifact
  | Region_id of Identifier.t
  | Text_range of Text_range.t
  | Row_filter of row_filter

val row_filter : where:(string * string) list -> (row_filter, string) result
val row_filter_where : row_filter -> (string * string) list
val compare : t -> t -> int
