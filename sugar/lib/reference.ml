type binding = Pinned | Tracking | Floating

type target = Region_address.t

type t = {
  id : Reference_id.t;
  target : target;
  binding : binding;
  expectations : Expectation.t list;
}

let make_target = Region_address.make

let make ~id ~target ~binding ?(expectations = []) () =
  let expectations = List.sort Expectation.compare expectations in
  let rec has_duplicate = function
    | left :: (right :: _ as rest) ->
        Expectation.compare left right = 0 || has_duplicate rest
    | [] | [ _ ] -> false
  in
  if has_duplicate expectations then
    Error "reference expectations must be unique"
  else
    match binding, Region_address.expectation target, expectations with
    | Pinned, None, [] ->
        Error "pinned reference requires an Observation expectation"
    | (Tracking | Floating), _, _ :: _ ->
        Error "tracking and floating references do not contain pinned expectations"
    | _ -> Ok { id; target; binding; expectations }

let id value = value.id
let target value = value.target
let binding value = value.binding
let expectations value = value.expectations
let resolution_expectations value =
  Option.to_list (Region_address.expectation value.target) @ value.expectations
let target_origin = Region_address.origin
let target_selector = Region_address.selector
let target_interpreter = Region_address.interpreter
let target_interpreter_version = Region_address.interpreter_version
let target_expectation = Region_address.expectation

let compare_target = Region_address.compare

let compare_binding left right =
  match (left, right) with
  | Pinned, Pinned | Tracking, Tracking | Floating, Floating -> 0
  | Pinned, (Tracking | Floating) -> -1
  | Tracking, Pinned -> 1
  | Tracking, Floating -> -1
  | Floating, (Pinned | Tracking) -> 1

let compare left right =
  match Reference_id.compare left.id right.id with
  | 0 -> (
      match Region_address.compare left.target right.target with
      | 0 -> (
          match compare_binding left.binding right.binding with
          | 0 -> List.compare Expectation.compare left.expectations right.expectations
          | other -> other)
      | other -> other)
  | other -> other

let equal left right = compare left right = 0
