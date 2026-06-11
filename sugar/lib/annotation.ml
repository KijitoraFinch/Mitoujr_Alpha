type subject = Region of Identifier.t

type object_ =
  | Region_object of Identifier.t
  | Reference_object of Identifier.t
  | Literal of string

type materialization =
  | Markdown_inline of { artifact : Identifier.t; range : Text_range.t }
  | Source_comment of { artifact : Identifier.t; range : Text_range.t }
  | Sidecar of { artifact : Identifier.t; path : Workspace_path.t option }
  | Generated_index of { artifact : Identifier.t }

type t = {
  id : Identifier.t;
  subject : subject;
  predicate : string;
  object_ : object_;
  provenance : Provenance.t list;
  materialization : materialization list;
}

let make ~id ~subject ~predicate ~object_ ~provenance ~materialization =
  if String.length predicate = 0 then Error "annotation predicate must not be empty"
  else Ok { id; subject; predicate; object_; provenance; materialization }

let id value = value.id
let subject value = value.subject
let predicate value = value.predicate
let object_ value = value.object_
let provenance value = value.provenance
let materialization value = value.materialization
