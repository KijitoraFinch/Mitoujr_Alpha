module type S = sig
  type t

  val make : scope:Origin.t -> local:string -> (t, string) result
  val scope : t -> Origin.t
  val local : t -> Identifier.t
  val compare : t -> t -> int
  val equal : t -> t -> bool
end

module Make () = struct
  type t = {
    scope : Origin.t;
    local : Identifier.t;
  }

  let make ~scope ~local =
    Identifier.make local |> Result.map (fun local -> { scope; local })

  let scope value = value.scope
  let local value = value.local

  let compare left right =
    match Origin.compare left.scope right.scope with
    | 0 -> Identifier.compare left.local right.local
    | other -> other

  let equal left right = compare left right = 0
end
