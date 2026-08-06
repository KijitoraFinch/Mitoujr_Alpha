type t = {
  origin : Origin.t;
  identity : Observation_identity.t;
}

let make ~origin ~identity = { origin; identity }
let origin value = value.origin

let observation_type value =
  Observation_identity.observation_type value.identity

let identity value = value.identity
let same left right = Observation_identity.equal left.identity right.identity
