(** The closed protocol-version and capability declaration stored in an
    extension manifest and returned during session initialization. *)
type t

val supported_protocol_version : string
val of_yojson : Yojson.Safe.t -> (t, string) result
val protocol_version : t -> string
val capability : t -> Capability.t
val equal : t -> t -> bool
