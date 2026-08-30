type object_ =
  | Region_object of Region_ref.t
  | Reference_object of Reference_id.t
  | Literal of string

type t = {
  id : Annotation_id.t;
  subject : Region_ref.t;
  predicate : string;
  object_ : object_;
}

let make ~id ~subject ~predicate ~object_ =
  if String.length predicate = 0 then Error "annotation predicate must not be empty"
  else if not (Utf8.is_valid predicate) then
    Error "annotation predicate must be valid UTF-8"
  else if
    match object_ with
    | Literal value -> not (Utf8.is_valid value)
    | Region_object _ | Reference_object _ -> false
  then Error "annotation literal must be valid UTF-8"
  else Ok { id; subject; predicate; object_ }

let id value = value.id
let subject value = value.subject
let predicate value = value.predicate
let object_ value = value.object_

let compare_object left right =
  match (left, right) with
  | Region_object left, Region_object right -> Region_ref.compare left right
  | Reference_object left, Reference_object right -> Reference_id.compare left right
  | Literal left, Literal right -> String.compare left right
  | Region_object _, (Reference_object _ | Literal _) -> -1
  | Reference_object _, Region_object _ -> 1
  | Reference_object _, Literal _ -> -1
  | Literal _, (Region_object _ | Reference_object _) -> 1

let compare left right =
  match Annotation_id.compare left.id right.id with
  | 0 -> (
      match Region_ref.compare left.subject right.subject with
      | 0 -> (
          match String.compare left.predicate right.predicate with
          | 0 -> compare_object left.object_ right.object_
          | other -> other)
      | other -> other)
  | other -> other

let equal left right = compare left right = 0
