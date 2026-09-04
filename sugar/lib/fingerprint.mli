(** A schema-named fingerprint emitted by an Interpreter. *)
type t = Schema_value.t

val make :
  schema:string -> value:Yojson.Safe.t -> unit -> (t, string) result

val sha256_schema : string
val sha256 : string -> t
val schema : t -> string
val value : t -> Normalized_value.t
val compare : t -> t -> int
val equal : t -> t -> bool
