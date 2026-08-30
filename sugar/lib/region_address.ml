type t = {
  origin : Observation.origin;
  selector : Selector.t;
  interpreter : Interpreter.t option;
  expectation : Expectation.t option;
}

let make ~origin ~selector ?interpreter ?interpreter_version ?expectation () =
  let whole = Selector.compare selector Selector.Whole_observation = 0 in
  match (whole, interpreter, interpreter_version) with
  | true, None, None ->
      Ok { origin; selector; interpreter = None; expectation }
  | true, Some _, _ | true, _, Some _ ->
      Error "whole region address must not specify an interpreter"
  | false, None, None ->
      Error "partial region address requires an exact interpreter identity"
  | false, None, Some _ ->
      Error "interpreter version requires an interpreter"
  | false, Some _, None ->
      Error "interpreter requires an interpreter version"
  | false, Some name, Some version ->
      Result.map
        (fun interpreter ->
          { origin; selector; interpreter = Some interpreter; expectation })
        (Interpreter.make ~name ~version ())

let origin value = value.origin
let selector value = value.selector
let interpreter value = Option.map Interpreter.name value.interpreter
let interpreter_version value = Option.map Interpreter.version value.interpreter
let interpreter_identity value = value.interpreter
let expectation value = value.expectation

let compare left right =
  match Observation.compare_origin left.origin right.origin with
  | 0 -> (
      match Selector.compare left.selector right.selector with
      | 0 -> (
          match
            Option.compare Interpreter.compare left.interpreter right.interpreter
          with
          | 0 -> Option.compare Expectation.compare left.expectation right.expectation
          | other -> other)
      | other -> other)
  | other -> other
