type flavor = Posix | Windows
type t

val of_native_string : flavor:flavor -> string -> (t, string) result
val of_segments : string list -> (t, string) result
val of_canonical_string : string -> (t, string) result
val segments : t -> string list
val to_canonical_string : t -> string
val compare : t -> t -> int
val equal : t -> t -> bool
