type endpoint = Region of Identifier.t | Reference of Identifier.t

type t = {
  id : Identifier.t;
  subject : endpoint;
  predicate : string;
  object_ : endpoint;
}

let make ~id ~subject ~predicate ~object_ =
  if String.length predicate = 0 then Error "relation predicate must not be empty"
  else Ok { id; subject; predicate; object_ }

let id value = value.id
let subject value = value.subject
let predicate value = value.predicate
let object_ value = value.object_
