type t = {
  origin : Observation.origin;
  selector : Selector.t;
  interpreter : Interpreter.t option;
}

let make ~origin ~selector ?interpreter ?interpreter_version () =
  if
    Selector.compare selector Selector.Whole_observation = 0
    && Option.is_some interpreter
  then Error "whole region address must not specify an interpreter"
  else
  match (interpreter, interpreter_version) with
  | None, None -> Ok { origin; selector; interpreter = None }
  | None, Some _ -> Error "interpreter version requires an interpreter"
  | Some _, None -> Error "interpreter requires an interpreter version"
  | Some name, Some version ->
      Result.map
        (fun interpreter -> { origin; selector; interpreter = Some interpreter })
        (Interpreter.make ~name ~version ())

let origin value = value.origin
let selector value = value.selector
let interpreter value = Option.map Interpreter.name value.interpreter
let interpreter_version value = Option.map Interpreter.version value.interpreter
let interpreter_identity value = value.interpreter

let compare left right =
  match Observation.compare_origin left.origin right.origin with
  | 0 -> (
      match Selector.compare left.selector right.selector with
      | 0 -> (
          Option.compare Interpreter.compare left.interpreter right.interpreter)
      | other -> other)
  | other -> other
