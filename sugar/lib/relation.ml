type endpoint = Region_ref.t

type t = {
  id : Annotation_id.t;
  subject : endpoint;
  predicate : string;
  object_ : endpoint;
  evidence : Annotation_occurrence.t Nonempty.t;
}

let make ~id ~subject ~predicate ~object_ ~evidence =
  if String.length predicate = 0 then Error "relation predicate must not be empty"
  else if not (Utf8.is_valid predicate) then
    Error "relation predicate must be valid UTF-8"
  else Ok { id; subject; predicate; object_; evidence }

let of_index_entry ~reference_index = function
  | Annotation_index.Conflict _ -> None
  | Annotation_index.Consistent { value = annotation; occurrences = evidence } ->
  let subject = Annotation.subject annotation in
  let object_ =
    match Annotation.object_ annotation with
    | Annotation.Region_object region -> Some region
    | Annotation.Reference_object reference -> (
        match Reference_index.find reference reference_index with
        | Some (Reference_index.Consistent { value; _ }) ->
            Some (Region_ref.Address (Reference.target value))
        | Some (Reference_index.Conflict _) | None -> None)
    | Annotation.Literal _ -> None
  in
  Option.map
    (fun object_ ->
      {
        id = Annotation.id annotation;
        subject;
        predicate = Annotation.predicate annotation;
        object_;
        evidence;
      })
    object_

let id value = value.id
let subject value = value.subject
let predicate value = value.predicate
let object_ value = value.object_
let evidence value = value.evidence
