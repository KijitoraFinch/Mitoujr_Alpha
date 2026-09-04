module type S = sig
  type t

  val make : scope:Origin.t -> local:string -> (t, string) result
  val scope : t -> Origin.t
  val local : t -> Identifier.t
  val compare : t -> t -> int
  val equal : t -> t -> bool
end

module Make () : S
