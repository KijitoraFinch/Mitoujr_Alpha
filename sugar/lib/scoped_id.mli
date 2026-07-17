module type S = sig
  type t

  val make : artifact:Artifact_id.t -> local:string -> (t, string) result
  val artifact : t -> Artifact_id.t
  val local : t -> Identifier.t
  val compare : t -> t -> int
  val equal : t -> t -> bool
end

module Make () : S
