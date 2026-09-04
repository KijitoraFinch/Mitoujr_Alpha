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

val in_observation :
  observation:Observation_id.t ->
  locator:observation_locator ->
  encoding:Observation_encoding.t ->
  t

val in_sidecar :
  path:Workspace_path.t ->
  content_identity:Content_identity.t ->
  locator:Structured_location.t ->
  ownership:ownership ->
  t

val compare : t -> t -> int
