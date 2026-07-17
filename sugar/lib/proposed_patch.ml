type t = {
  id : Patch_id.t;
  target : Workspace_path.t;
  expected_identity : Content_identity.t;
  resulting_identity : Content_identity.t;
  edits : Text_edit.t list;
  reason : string;
  provenance : Provenance.t;
}

let make ~id ~target ~expected_identity ~resulting_identity ~edits ~reason
    ~provenance =
  if edits = [] then Error "proposed patch must contain at least one edit"
  else if String.length reason = 0 then Error "patch reason must not be empty"
  else if not (Utf8.is_valid reason) then Error "patch reason must be valid UTF-8"
  else if
    List.exists
      (fun edit -> not (Utf8.is_valid (Text_edit.replacement edit)))
      edits
  then Error "text edit replacement must be valid UTF-8"
  else
    Ok
      {
        id;
        target;
        expected_identity;
        resulting_identity;
        edits;
        reason;
        provenance;
      }

let id value = value.id
let target value = value.target
let expected_identity value = value.expected_identity
let resulting_identity value = value.resulting_identity
let edits value = value.edits
let reason value = value.reason
let provenance value = value.provenance

let compare left right =
  match Workspace_path.compare left.target right.target with
  | 0 -> Patch_id.compare left.id right.id
  | other -> other
