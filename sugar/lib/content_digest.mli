type t

val of_hex : string -> (t, string) result
val of_content : string -> t

module Incremental : sig
  type state

  val empty : unit -> state
  val feed_bytes :
    state -> bytes -> offset:int -> length:int -> (state, string) result
  val finish : state -> t
end

val to_hex : t -> string
val to_string : t -> string
val compare : t -> t -> int
val equal : t -> t -> bool
