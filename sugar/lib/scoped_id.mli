module type S = sig
  type t

  val make : observation:Observation_id.t -> local:string -> (t, string) result
  val observation : t -> Observation_id.t
  val local : t -> Identifier.t
  val compare : t -> t -> int
  val equal : t -> t -> bool
end

module Make () : S
