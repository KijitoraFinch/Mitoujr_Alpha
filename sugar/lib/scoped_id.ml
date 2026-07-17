module type S = sig
  type t

  val make : artifact:Artifact_id.t -> local:string -> (t, string) result
  val artifact : t -> Artifact_id.t
  val local : t -> Identifier.t
  val compare : t -> t -> int
  val equal : t -> t -> bool
end

module Make () = struct
  type t = {
    artifact : Artifact_id.t;
    local : Identifier.t;
  }

  let make ~artifact ~local =
    Identifier.make local |> Result.map (fun local -> { artifact; local })

  let artifact value = value.artifact
  let local value = value.local

  let compare left right =
    match Artifact_id.compare left.artifact right.artifact with
    | 0 -> Identifier.compare left.local right.local
    | other -> other

  let equal left right = compare left right = 0
end
