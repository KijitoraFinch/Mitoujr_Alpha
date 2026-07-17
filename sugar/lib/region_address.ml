type t = {
  artifact : Artifact.origin;
  selector : Selector.t;
  interpreter : string option;
}

let make ~artifact ~selector ?interpreter () =
  match interpreter with
  | Some "" -> Error "interpreter must not be empty"
  | Some value when not (Utf8.is_valid value) ->
      Error "interpreter must be valid UTF-8"
  | _ -> Ok { artifact; selector; interpreter }

let artifact value = value.artifact
let selector value = value.selector
let interpreter value = value.interpreter

let compare left right =
  match Artifact.compare_origin left.artifact right.artifact with
  | 0 -> (
      match Selector.compare left.selector right.selector with
      | 0 -> Option.compare String.compare left.interpreter right.interpreter
      | other -> other)
  | other -> other
