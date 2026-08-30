type source_occurrence =
  | Annotation of Annotation_occurrence.t
  | Reference_definition of Reference_definition_occurrence.t

type t = {
  source_occurrence : source_occurrence;
  target_origin : Origin.t;
  target_encoding : string;
  policy : Normalized_value.t;
}

let make ~source_occurrence ~target_origin ~target_encoding ~policy () =
  if String.length target_encoding = 0 then
    Error "DeriveRequest target encoding must not be empty"
  else if not (Utf8.is_valid target_encoding) then
    Error "DeriveRequest target encoding must be valid UTF-8"
  else
    Normalized_value.make ~path:"$deriveRequest.policy" policy
    |> Result.map (fun policy ->
           { source_occurrence; target_origin; target_encoding; policy })

let inline_to_sidecar ~source_occurrence path =
  let origin = Origin.workspace path in
  make ~source_occurrence ~target_origin:origin
    ~target_encoding:"https://monika.local/encodings/sidecar-v2#derived"
    ~policy:
      (`Assoc
        [
          ("includeReferencedDefinition", `Bool true);
          ("unrelatedDerivedEntries", `String "preserve");
        ])
    ()
  |> Result.get_ok

let source_occurrence value = value.source_occurrence
let target_origin value = value.target_origin
let target_encoding value = value.target_encoding
let policy value = value.policy

let compare_source left right =
  match left, right with
  | Annotation left, Annotation right ->
      Annotation_occurrence.compare left right
  | Reference_definition left, Reference_definition right ->
      Reference_definition_occurrence.compare left right
  | Annotation _, Reference_definition _ -> -1
  | Reference_definition _, Annotation _ -> 1

let compare left right =
  match compare_source left.source_occurrence right.source_occurrence with
  | 0 -> (
      match Origin.compare left.target_origin right.target_origin with
      | 0 -> (
          match String.compare left.target_encoding right.target_encoding with
          | 0 -> Normalized_value.compare left.policy right.policy
          | other -> other)
      | other -> other)
  | other -> other
