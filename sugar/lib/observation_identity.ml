type t = {
  observation_type : Observation_type.t;
  key : string;
}

let make ~observation_type ~key () =
  if String.length key = 0 then
    Error "observation identity key must not be empty"
  else if not (Utf8.is_valid key) then
    Error "observation identity key must be valid UTF-8"
  else Ok { observation_type; key }

let of_content ~observation_type content_identity =
  let key =
    Printf.sprintf "%s;size=%d"
      (Content_identity.display_hash content_identity)
      (Content_identity.byte_length content_identity)
  in
  { observation_type; key }

let observation_type value = value.observation_type
let key value = value.key

let compare left right =
  match
    Observation_type.compare left.observation_type right.observation_type
  with
  | 0 -> String.compare left.key right.key
  | other -> other

let equal left right = compare left right = 0
