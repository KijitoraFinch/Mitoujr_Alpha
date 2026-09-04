type t = {
  interpreter : Interpreter.t;
  observation_identity : Observation_identity.t;
  selector : Selector.t;
}

let make ~interpreter ~observation_identity ~selector =
  { interpreter; observation_identity; selector }

let interpreter value = value.interpreter
let observation_identity value = value.observation_identity
let selector value = value.selector

let compare left right =
  match Interpreter.compare left.interpreter right.interpreter with
  | 0 -> (
      match
        Observation_identity.compare left.observation_identity
          right.observation_identity
      with
      | 0 -> Selector.compare left.selector right.selector
      | other -> other)
  | other -> other

let equal left right = compare left right = 0
