type observation_locator =
  | Byte_range of Text_range.t
  | Structured of Structured_location.t

type ownership = Authored | Derived

type t =
  | In_observation of {
      observation : Observation_id.t;
      locator : observation_locator;
      encoding : Observation_encoding.t;
    }
  | In_sidecar of {
      path : Workspace_path.t;
      content_identity : Content_identity.t;
      locator : Structured_location.t;
      ownership : ownership;
    }

let in_observation ~observation ~locator ~encoding =
  In_observation { observation; locator; encoding }

let in_sidecar ~path ~content_identity ~locator ~ownership =
  In_sidecar { path; content_identity; locator; ownership }

let compare_observation_locator left right =
  match (left, right) with
  | Byte_range left, Byte_range right -> Text_range.compare left right
  | Structured left, Structured right -> Structured_location.compare left right
  | Byte_range _, Structured _ -> -1
  | Structured _, Byte_range _ -> 1

let compare_ownership left right =
  match (left, right) with
  | Authored, Authored | Derived, Derived -> 0
  | Authored, Derived -> -1
  | Derived, Authored -> 1

let compare left right =
  match (left, right) with
  | In_observation left, In_observation right -> (
      match Observation_id.compare left.observation right.observation with
      | 0 -> (
          match compare_observation_locator left.locator right.locator with
          | 0 -> Observation_encoding.compare left.encoding right.encoding
          | other -> other)
      | other -> other)
  | In_sidecar left, In_sidecar right -> (
      match Workspace_path.compare left.path right.path with
      | 0 -> (
          match Content_identity.compare left.content_identity right.content_identity with
          | 0 -> (
              match Structured_location.compare left.locator right.locator with
              | 0 -> compare_ownership left.ownership right.ownership
              | other -> other)
          | other -> other)
      | other -> other)
  | In_observation _, In_sidecar _ -> -1
  | In_sidecar _, In_observation _ -> 1
