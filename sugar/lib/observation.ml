type origin = Origin.t

type structured_value = {
  schema : string;
  value : Normalized_value.t;
}

type representation =
  | Bytes of string
  | Structured of structured_value

type t = {
  id : Observation_id.t;
  origin : Origin.t;
  identity : Observation_identity.t;
  representation : representation;
  content_identity : Content_identity.t option;
}

let workspace = Origin.workspace
let git = Origin.git
let web = Origin.web
let generated = Origin.generated
let external_ = Origin.external_
let extension = Origin.extension

let make ~id ~origin ~identity ~representation () =
  match representation with
  | Bytes bytes ->
      Ok
        {
          id;
          origin;
          identity;
          representation;
          content_identity = Some (Content_identity.of_content bytes);
        }
  | Structured { schema; _ } when String.length schema = 0 ->
      Error "structured observation schema must not be empty"
  | Structured { schema; _ } when not (Utf8.is_valid schema) ->
      Error "structured observation schema must be valid UTF-8"
  | Structured _ ->
      Ok { id; origin; identity; representation; content_identity = None }

let of_bytes ~id ~origin ~observation_type ~bytes =
  let content_identity = Content_identity.of_content bytes in
  let identity =
    Observation_identity.of_content ~observation_type content_identity
  in
  {
    id;
    origin;
    identity;
    representation = Bytes bytes;
    content_identity = Some content_identity;
  }

let of_structured ~id ~origin ~identity ~schema ~value () =
  Result.bind
    (Normalized_value.make ~path:"$observation.representation.value" value)
    (fun value ->
      make ~id ~origin ~identity
        ~representation:(Structured { schema; value }) ())

let id value = value.id
let origin value = value.origin

let observation_type value =
  Observation_identity.observation_type value.identity

let identity value = value.identity
let representation value = value.representation

let bytes value =
  match value.representation with Bytes bytes -> Some bytes | Structured _ -> None

let content_identity value = value.content_identity
let same left right = Observation_identity.equal left.identity right.identity
let compare_origin = Origin.compare
