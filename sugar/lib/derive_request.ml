type t = {
  source_origin : Origin.t;
  target_origin : Origin.t;
  target_encoding : string;
  policy : Normalized_value.t;
}

let make ~source_origin ~target_origin ~target_encoding ~policy () =
  if String.length target_encoding = 0 then
    Error "DeriveRequest target encoding must not be empty"
  else if not (Utf8.is_valid target_encoding) then
    Error "DeriveRequest target encoding must be valid UTF-8"
  else
    Normalized_value.make ~path:"$deriveRequest.policy" policy
    |> Result.map (fun policy ->
           { source_origin; target_origin; target_encoding; policy })

let inline_to_sidecar path =
  let origin = Origin.workspace path in
  make ~source_origin:origin ~target_origin:origin
    ~target_encoding:"https://monika.local/encodings/sidecar-v2#derived"
    ~policy:
      (`Assoc
        [
          ("annotationSelection", `String "all-in-observation");
          ("includeReferencedDefinitions", `Bool true);
        ])
    ()
  |> Result.get_ok

let source_origin value = value.source_origin
let target_origin value = value.target_origin
let target_encoding value = value.target_encoding
let policy value = value.policy

let compare left right =
  match Origin.compare left.source_origin right.source_origin with
  | 0 -> (
      match Origin.compare left.target_origin right.target_origin with
      | 0 -> (
          match String.compare left.target_encoding right.target_encoding with
          | 0 -> Normalized_value.compare left.policy right.policy
          | other -> other)
      | other -> other)
  | other -> other
