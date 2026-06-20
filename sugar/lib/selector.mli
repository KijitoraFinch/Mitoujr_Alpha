module Field_name : sig
  type t

  val make : string -> (t, string) result
  val to_string : t -> string
  val compare : t -> t -> int
end

module Literal : sig
  type t =
    | String of string
    | Int of int
    | Bool of bool

  val compare : t -> t -> int
end

module Row_filter : sig
  type t

  val make : (Field_name.t * Literal.t) list -> (t, string) result
  val conditions : t -> (Field_name.t * Literal.t) list
  val compare : t -> t -> int
end

type t =
  | Whole_artifact
  | Region_id of Identifier.t
  | Text_range of Text_range.t
  | Row_filter of Row_filter.t

val compare : t -> t -> int
