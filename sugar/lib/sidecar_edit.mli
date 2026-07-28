val validate_layout_profile : string -> (unit, string) result

val optional_derived_section_range :
  string -> (Text_range.t option, string) result

val derived_section_range : string -> (Text_range.t, string) result

val derived_insertion_offset : string -> (int, string) result
