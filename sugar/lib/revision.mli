(** A schema-named Resource revision value. *)
type t = Schema_value.t

val make :
  schema:string -> value:Yojson.Safe.t -> unit -> (t, string) result

val git_schema : string
val of_origin : Origin.t -> t option
val schema : t -> string
val value : t -> Normalized_value.t
val compare : t -> t -> int
val equal : t -> t -> bool
