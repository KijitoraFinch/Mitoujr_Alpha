type origin = Origin.t

type t = {
  id : Observation_id.t;
  origin : Origin.t;
  identity : Observation_identity.t;
  content_identity : Content_identity.t option;
}

let workspace = Origin.workspace
let git = Origin.git
let web = Origin.web
let generated = Origin.generated
let external_ = Origin.external_
let extension = Origin.extension

let make ~id ~origin ~identity ?content_identity () =
  { id; origin; identity; content_identity }

let of_content ~id ~origin ~observation_type ~content_identity =
  let identity =
    Observation_identity.of_content ~observation_type content_identity
  in
  { id; origin; identity; content_identity = Some content_identity }

let id value = value.id
let origin value = value.origin

let observation_type value =
  Observation_identity.observation_type value.identity

let identity value = value.identity
let content_identity value = value.content_identity
let same left right = Observation_identity.equal left.identity right.identity
let compare_origin = Origin.compare
