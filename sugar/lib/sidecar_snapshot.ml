type t = {
  path : Workspace_path.t;
  content_identity : Content_identity.t;
  bytes : string;
}

let of_bytes ~path bytes =
  { path; content_identity = Content_identity.of_content bytes; bytes }

let make ~path ~content_identity ~bytes =
  if Content_identity.equal content_identity (Content_identity.of_content bytes) then
    Ok { path; content_identity; bytes }
  else Error "sidecar snapshot content identity does not match its bytes"

let path value = value.path
let content_identity value = value.content_identity
let bytes value = value.bytes

let compare left right =
  match Workspace_path.compare left.path right.path with
  | 0 -> Content_identity.compare left.content_identity right.content_identity
  | other -> other
