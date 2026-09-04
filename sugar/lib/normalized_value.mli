(** A canonical, protocol-safe JSON value. Object members are ordered by name,
    duplicate names are rejected, strings are valid UTF-8, and integers fit the
    protocol safe-integer domain. *)
type t

val make : ?path:string -> Yojson.Safe.t -> (t, string) result
val to_yojson : t -> Yojson.Safe.t
val canonical_json : t -> string
val compare : t -> t -> int
val equal : t -> t -> bool
