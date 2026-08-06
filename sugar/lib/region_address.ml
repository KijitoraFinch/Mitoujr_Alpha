type t = {
  artifact : Artifact.origin;
  selector : Selector.t;
  interpreter : string option;
  interpreter_version : string option;
}

let make ~artifact ~selector ?interpreter ?interpreter_version () =
  if
    Selector.compare selector Selector.Whole_artifact = 0
    && Option.is_some interpreter
  then Error "whole region address must not specify an interpreter"
  else
  match (interpreter, interpreter_version) with
  | None, None ->
      Ok { artifact; selector; interpreter = None; interpreter_version = None }
  | None, Some _ -> Error "interpreter version requires an interpreter"
  | Some name, version ->
      let version = Option.value ~default:"1" version in
      Result.map
        (fun identity ->
          {
            artifact;
            selector;
            interpreter = Some (Interpreter.name identity);
            interpreter_version = Some (Interpreter.version identity);
          })
        (Interpreter.make ~name ~version ())

let artifact value = value.artifact
let selector value = value.selector
let interpreter value = value.interpreter
let interpreter_version value = value.interpreter_version

let interpreter_identity value =
  match (value.interpreter, value.interpreter_version) with
  | Some name, Some version ->
      Some (Interpreter.make ~name ~version () |> Result.get_ok)
  | None, None -> None
  | _ -> invalid_arg "invalid RegionAddress interpreter identity"

let compare left right =
  match Artifact.compare_origin left.artifact right.artifact with
  | 0 -> (
      match Selector.compare left.selector right.selector with
      | 0 -> (
          match Option.compare String.compare left.interpreter right.interpreter with
          | 0 ->
              Option.compare String.compare left.interpreter_version
                right.interpreter_version
          | other -> other)
      | other -> other)
  | other -> other
