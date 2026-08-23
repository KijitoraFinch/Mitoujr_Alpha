type t = {
  target : Reference.target;
  observation_identity : Observation_identity.t;
  region_fingerprint : string option;
  display : string option;
  observed_at : string;
}

let make ~target ~observation_identity ?region_fingerprint ?display ~observed_at ()
    =
  if String.length observed_at = 0 then Error "observation time must not be empty"
  else if not (Utf8.is_valid observed_at) then
    Error "observation time must be valid UTF-8"
  else if
    Option.fold ~none:false ~some:(Fun.negate Utf8.is_valid)
      region_fingerprint
  then
    Error "region fingerprint must be valid UTF-8"
  else if Option.fold ~none:false ~some:(Fun.negate Utf8.is_valid) display then
    Error "snapshot display must be valid UTF-8"
  else
    Ok
      {
        target;
        observation_identity;
        region_fingerprint;
        display;
        observed_at;
      }

let target value = value.target
let observation_identity value = value.observation_identity
let region_fingerprint value = value.region_fingerprint
let display value = value.display
let observed_at value = value.observed_at

let compare left right =
  match Reference.compare_target left.target right.target with
  | 0 -> String.compare left.observed_at right.observed_at
  | other -> other
