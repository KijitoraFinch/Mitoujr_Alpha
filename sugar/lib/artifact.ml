type origin = Origin.t

type t = {
  id : Artifact_id.t;
  media_type : string option;
  content_identity : Content_identity.t;
  observation : Observation.t;
}

let workspace = Origin.workspace
let git = Origin.git
let web = Origin.web
let generated = Origin.generated
let external_ = Origin.external_
let extension = Origin.extension

let make ~id ~origin ?media_type ~content_identity () =
  let observation_type =
    match media_type with
    | None -> Ok Observation_type.binary
    | Some media_type ->
        Observation_type.make ~name:media_type ~version:"1" ()
  in
  Result.map
    (fun observation_type ->
      let identity =
        Observation_identity.of_content ~observation_type content_identity
      in
      let observation = Observation.make ~origin ~identity in
      { id; media_type; content_identity; observation })
    observation_type

let id value = value.id
let origin value = Observation.origin value.observation
let media_type value = value.media_type
let content_identity value = value.content_identity
let observation value = value.observation
let observation_identity value = Observation.identity value.observation
let compare_origin = Origin.compare
