(** A schema-named, canonical protocol value. *)
type t

val make :
  schema:string -> value:Yojson.Safe.t -> unit -> (t, string) result

val schema : t -> string
val value : t -> Normalized_value.t
val compare : t -> t -> int
val equal : t -> t -> bool
