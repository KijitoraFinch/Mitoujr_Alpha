type endpoint = Region of Region_ref.t | Reference of Reference_id.t

type t = {
  id : Identifier.t;
  subject : endpoint;
  predicate : string;
  object_ : endpoint;
}

let make ~id ~subject ~predicate ~object_ =
  if String.length predicate = 0 then Error "relation predicate must not be empty"
  else if not (Utf8.is_valid predicate) then
    Error "relation predicate must be valid UTF-8"
  else Ok { id; subject; predicate; object_ }

let id value = value.id
let subject value = value.subject
let predicate value = value.predicate
let object_ value = value.object_
