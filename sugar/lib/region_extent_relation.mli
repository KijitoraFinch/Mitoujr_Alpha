(** The closed, exhaustive relation between two region extents in one fixed
    observation. The constructors are read as [left relation right]. *)
type t = Equal | Contains | Contained_by | Overlaps | Disjoint

val to_string : t -> string
val of_string : string -> (t, string) result
val invert : t -> t

(** Classifies extents represented by built-in regions. Whole-observation
    regions are handled by the core. Partial regions require byte ranges and
    the same interpreter identity. This function never treats selector or
    region-ID equality as extent equality. *)
val classify_builtin : Region.t -> Region.t -> (t, string) result
