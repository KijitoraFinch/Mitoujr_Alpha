type t = Equal | Contains | Contained_by | Overlaps | Disjoint

let to_string = function
  | Equal -> "equal"
  | Contains -> "contains"
  | Contained_by -> "contained-by"
  | Overlaps -> "overlaps"
  | Disjoint -> "disjoint"

let of_string = function
  | "equal" -> Ok Equal
  | "contains" -> Ok Contains
  | "contained-by" -> Ok Contained_by
  | "overlaps" -> Ok Overlaps
  | "disjoint" -> Ok Disjoint
  | value -> Error ("unknown region extent relation: " ^ value)

let invert = function
  | Equal -> Equal
  | Contains -> Contained_by
  | Contained_by -> Contains
  | Overlaps -> Overlaps
  | Disjoint -> Disjoint

let same_observation left right =
  Observation_id.equal (Region.observation left) (Region.observation right)
  && Observation_identity.equal (Region.observation_identity left)
       (Region.observation_identity right)

let is_whole region =
  Selector.compare (Region.selector region) Selector.Whole_observation = 0

let classify_ranges left right =
  let left_start = Text_range.start left in
  let left_end = Text_range.end_ left in
  let right_start = Text_range.start right in
  let right_end = Text_range.end_ right in
  if left_start = right_start && left_end = right_end then Equal
  else if left_start <= right_start && right_end <= left_end then Contains
  else if right_start <= left_start && left_end <= right_end then Contained_by
  else if left_start < right_end && right_start < left_end then Overlaps
  else Disjoint

let classify_builtin left right =
  if not (same_observation left right) then
    Error "region extents belong to different observations"
  else
    match (is_whole left, is_whole right) with
    | true, true -> Ok Equal
    | true, false -> Ok Contains
    | false, true -> Ok Contained_by
    | false, false -> (
        match
          ( Region.interpreter_identity left,
            Region.interpreter_identity right,
            Region.range left,
            Region.range right )
        with
        | Some left_interpreter, Some right_interpreter, Some left, Some right
          when Interpreter.equal left_interpreter right_interpreter ->
            Ok (classify_ranges left right)
        | Some left, Some right, _, _
          when not (Interpreter.equal left right) ->
            Error "cannot compare region extents from different interpreters"
        | _, _, None, _ | _, _, _, None ->
            Error "built-in region extent classification requires byte ranges"
        | _ -> Error "partial regions do not have interpreter identities")
