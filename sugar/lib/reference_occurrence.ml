type target = Named of Reference_id.t | Direct of Region_address.t

type t = {
  source_observation : Observation_id.t;
  source_region : Region_id.t option;
  range : Text_range.t;
  target : target;
}

let make ~source_observation ?source_region ~range ~target () =
  match source_region with
  | Some region
    when not (Observation_id.equal source_observation (Region_id.observation region)) ->
      Error "reference occurrence region must belong to its source observation"
  | None | Some _ -> Ok { source_observation; source_region; range; target }

let source_observation value = value.source_observation
let source_region value = value.source_region
let range value = value.range
let target value = value.target

let compare_target left right =
  match (left, right) with
  | Named left, Named right -> Reference_id.compare left right
  | Direct left, Direct right -> Region_address.compare left right
  | Named _, Direct _ -> -1
  | Direct _, Named _ -> 1

let compare left right =
  match Observation_id.compare left.source_observation right.source_observation with
  | 0 -> (
      match Option.compare Region_id.compare left.source_region right.source_region with
      | 0 -> (
          match Text_range.compare left.range right.range with
          | 0 -> compare_target left.target right.target
          | other -> other)
      | other -> other)
  | other -> other
