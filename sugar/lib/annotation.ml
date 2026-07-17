type subject = Region of Region_ref.t

type object_ =
  | Region_object of Region_ref.t
  | Reference_object of Reference_id.t
  | Literal of string

type materialization =
  | Markdown_inline of { artifact : Artifact_id.t; range : Text_range.t }
  | Source_comment of { artifact : Artifact_id.t; range : Text_range.t }
  | Sidecar of { artifact : Artifact_id.t; path : Workspace_path.t option }
  | Generated_index of { artifact : Artifact_id.t }

type t = {
  id : Annotation_id.t;
  subject : subject;
  predicate : string;
  object_ : object_;
  provenance : Provenance.t list;
  materialization : materialization list;
}

let make ~id ~subject ~predicate ~object_ ~provenance ~materialization =
  if String.length predicate = 0 then Error "annotation predicate must not be empty"
  else if not (Utf8.is_valid predicate) then
    Error "annotation predicate must be valid UTF-8"
  else if
    match object_ with
    | Literal value -> not (Utf8.is_valid value)
    | Region_object _ | Reference_object _ -> false
  then Error "annotation literal must be valid UTF-8"
  else Ok { id; subject; predicate; object_; provenance; materialization }

let id value = value.id
let subject value = value.subject
let predicate value = value.predicate
let object_ value = value.object_
let provenance value = value.provenance
let materialization value = value.materialization
