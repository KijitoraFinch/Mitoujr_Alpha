type binding = Pinned | Tracking | Floating

type target = {
  artifact : Artifact.origin;
  selector : Selector.t option;
  interpreter : string option;
}

type t = {
  id : Identifier.t;
  target : target;
  binding : binding;
  expectations : Expectation.t list;
  provenance : Provenance.t list;
}

let make ~id ~target ~binding ?(expectations = []) ?(provenance = []) () =
  { id; target; binding; expectations; provenance }

let id value = value.id
let target value = value.target
let binding value = value.binding
let expectations value = value.expectations
let provenance value = value.provenance

let compare_target left right =
  match Artifact.compare_origin left.artifact right.artifact with
  | 0 -> (
      match Option.compare Selector.compare left.selector right.selector with
      | 0 -> Option.compare String.compare left.interpreter right.interpreter
      | other -> other)
  | other -> other
