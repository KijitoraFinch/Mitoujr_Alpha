type t

val make :
  schema:string -> value:Yojson.Safe.t -> (t, string) result

val schema : t -> string
val value : t -> Yojson.Safe.t
val compare : t -> t -> int
