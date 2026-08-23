module type S = sig
  type t

  val make : observation:Observation_id.t -> local:string -> (t, string) result
  val observation : t -> Observation_id.t
  val local : t -> Identifier.t
  val compare : t -> t -> int
  val equal : t -> t -> bool
end

module Make () = struct
  type t = {
    observation : Observation_id.t;
    local : Identifier.t;
  }

  let make ~observation ~local =
    Identifier.make local |> Result.map (fun local -> { observation; local })

  let observation value = value.observation
  let local value = value.local

  let compare left right =
    match Observation_id.compare left.observation right.observation with
    | 0 -> Identifier.compare left.local right.local
    | other -> other

  let equal left right = compare left right = 0
end
