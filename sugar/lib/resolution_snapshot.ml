type t = {
  target : Reference.target;
  artifact_identity : Content_identity.t;
  region_fingerprint : string option;
  display : string option;
  observed_at : string;
}

let make ~target ~artifact_identity ?region_fingerprint ?display ~observed_at ()
    =
  if String.length observed_at = 0 then Error "observation time must not be empty"
  else
    Ok
      {
        target;
        artifact_identity;
        region_fingerprint;
        display;
        observed_at;
      }

let target value = value.target
let artifact_identity value = value.artifact_identity
let region_fingerprint value = value.region_fingerprint
let display value = value.display
let observed_at value = value.observed_at

let compare left right =
  match Reference.compare_target left.target right.target with
  | 0 -> String.compare left.observed_at right.observed_at
  | other -> other
