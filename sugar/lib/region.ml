type basis =
  | Whole of Observation_identity.t
  | Resolved of Region_resolution.t

type t = {
  id : Region_id.t;
  basis : basis;
  summary : string option;
  range : Text_range.t option;
  fingerprint : string option;
}

let make ~id ~observation_identity ~selector ~interpreter ?summary ?range
    ?fingerprint () =
  if Selector.compare selector Selector.Whole_artifact = 0 then
    Error "interpreted region must not use the whole-artifact selector"
  else if Option.fold ~none:false ~some:(Fun.negate Utf8.is_valid) summary then
    Error "region summary must be valid UTF-8"
  else if
    Option.fold ~none:false ~some:(Fun.negate Utf8.is_valid) fingerprint
  then Error "region fingerprint must be valid UTF-8"
  else
    Ok
      {
        id;
        basis =
          Resolved
            (Region_resolution.make ~interpreter ~observation_identity
               ~selector);
        summary;
        range;
        fingerprint;
      }

let whole ~id ~observation_identity =
  {
    id;
    basis = Whole observation_identity;
    summary = None;
    range = None;
    fingerprint = None;
  }

let id value = value.id
let artifact value = Region_id.artifact value.id
let observation_identity value =
  match value.basis with
  | Whole identity -> identity
  | Resolved resolution -> Region_resolution.observation_identity resolution

let selector value =
  match value.basis with
  | Whole _ -> Selector.Whole_artifact
  | Resolved resolution -> Region_resolution.selector resolution

let interpreter value =
  match value.basis with
  | Resolved resolution ->
      Some (Region_resolution.interpreter resolution |> Interpreter.name)
  | Whole _ -> None

let interpreter_identity value =
  match value.basis with
  | Resolved resolution -> Some (Region_resolution.interpreter resolution)
  | Whole _ -> None
let summary value = value.summary
let range value = value.range
let fingerprint value = value.fingerprint
