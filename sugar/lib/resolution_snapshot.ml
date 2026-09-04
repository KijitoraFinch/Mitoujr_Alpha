type t = {
  target : Reference.target;
  observation_identity : Observation_identity.t;
  region_fingerprint : Fingerprint.t option;
  display : string option;
  observed_at : string;
}

let make ~target ~observation_identity ?region_fingerprint ?display ~observed_at ()
    =
  if String.length observed_at = 0 then Error "observation time must not be empty"
  else if not (Utf8.is_valid observed_at) then
    Error "observation time must be valid UTF-8"
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

let same_resolution left right =
  Reference.compare_target left.target right.target = 0
  && Observation_identity.equal left.observation_identity
       right.observation_identity
  && Option.equal Fingerprint.equal left.region_fingerprint
       right.region_fingerprint

let compare left right =
  match Reference.compare_target left.target right.target with
  | 0 -> (
      match
        Observation_identity.compare left.observation_identity
          right.observation_identity
      with
      | 0 -> (
          match
            Option.compare Fingerprint.compare left.region_fingerprint
              right.region_fingerprint
          with
          | 0 -> (
              match Option.compare String.compare left.display right.display with
              | 0 -> String.compare left.observed_at right.observed_at
              | other -> other)
          | other -> other)
      | other -> other)
  | other -> other
