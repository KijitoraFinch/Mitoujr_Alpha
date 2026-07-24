type target = Named of Reference_id.t | Direct of Region_address.t

type t = {
  source_artifact : Artifact_id.t;
  source_region : Region_id.t option;
  range : Text_range.t;
  target : target;
}

let make ~source_artifact ?source_region ~range ~target () =
  match source_region with
  | Some region
    when not (Artifact_id.equal source_artifact (Region_id.artifact region)) ->
      Error "reference occurrence region must belong to its source artifact"
  | None | Some _ -> Ok { source_artifact; source_region; range; target }

let source_artifact value = value.source_artifact
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
  match Artifact_id.compare left.source_artifact right.source_artifact with
  | 0 -> (
      match Option.compare Region_id.compare left.source_region right.source_region with
      | 0 -> (
          match Text_range.compare left.range right.range with
          | 0 -> compare_target left.target right.target
          | other -> other)
      | other -> other)
  | other -> other
