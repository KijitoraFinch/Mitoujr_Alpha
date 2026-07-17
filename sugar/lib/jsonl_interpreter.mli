type match_ = {
  range : Text_range.t;
  display : string;
}

type selection = No_match | One of match_ | Ambiguous

val select : Selector.Row_filter.t -> string -> (selection, string) result
