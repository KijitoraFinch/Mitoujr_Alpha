let ( let* ) = Result.bind

type operation =
  | Create of { content : string }
  | Edit of {
      expected_identity : Content_identity.t;
      edits : Text_edit.t list;
    }

type t = {
  id : Patch_id.t;
  target : Workspace_path.t;
  operation : operation;
  resulting_identity : Content_identity.t;
  reason : string;
  provenance : Provenance.t;
}

let validate_common ~resulting_identity ~reason ~provenance:_ =
  if String.length reason = 0 then Error "patch reason must not be empty"
  else if not (Utf8.is_valid reason) then Error "patch reason must be valid UTF-8"
  else if
    not (Protocol_integer.is_nonnegative_safe (Content_identity.byte_length resulting_identity))
  then Error "patch resulting content length exceeds the protocol integer range"
  else Ok ()

let make ~id ~target ~expected_identity ~resulting_identity ~edits ~reason
    ~provenance =
  if edits = [] then Error "edit patch must contain at least one edit"
  else if
    List.exists
      (fun edit -> not (Utf8.is_valid (Text_edit.replacement edit)))
      edits
  then Error "text edit replacement must be valid UTF-8"
  else
    let* () = validate_common ~resulting_identity ~reason ~provenance in
    Ok
      {
        id;
        target;
        operation = Edit { expected_identity; edits };
        resulting_identity;
        reason;
        provenance;
      }

let make_create ~id ~target ~resulting_identity ~content ~reason ~provenance =
  if not (Utf8.is_valid content) then
    Error "create patch content must be valid UTF-8"
  else if
    not
      (Content_identity.equal resulting_identity
         (Content_identity.of_content content))
  then Error "create patch content does not match its resulting identity"
  else
    let* () = validate_common ~resulting_identity ~reason ~provenance in
    Ok
      {
        id;
        target;
        operation = Create { content };
        resulting_identity;
        reason;
        provenance;
      }

let id value = value.id
let target value = value.target
let operation value = value.operation
let expected_identity value =
  match value.operation with
  | Create _ -> None
  | Edit value -> Some value.expected_identity

let resulting_identity value = value.resulting_identity
let edits value =
  match value.operation with Create _ -> [] | Edit value -> value.edits

let create_content value =
  match value.operation with
  | Create value -> Some value.content
  | Edit _ -> None

let reason value = value.reason
let provenance value = value.provenance

let compare left right =
  match Workspace_path.compare left.target right.target with
  | 0 -> Patch_id.compare left.id right.id
  | other -> other
