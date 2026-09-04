type operation = Read | Decode

type t = {
  path : Workspace_path.t;
  content_identity : Content_identity.t option;
  operation : operation;
  code : string;
  message : string;
}

let valid_text value = String.length value > 0 && Utf8.is_valid value

let make ~path ?content_identity ~operation ~code ~message () =
  if not (valid_text code) then
    Error "metadata failure code must be non-empty UTF-8"
  else if not (valid_text message) then
    Error "metadata failure message must be non-empty UTF-8"
  else Ok { path; content_identity; operation; code; message }

let path value = value.path
let content_identity value = value.content_identity
let operation value = value.operation
let code value = value.code
let message value = value.message
let operation_string = function Read -> "read" | Decode -> "decode"

let to_diagnostic value =
  let path = Workspace_path.to_canonical_string value.path in
  let diagnostic_code =
    match value.operation with
    | Read -> Diagnostic.Metadata_failure
    | Decode -> Diagnostic.Invalid_sidecar
  in
  Diagnostic.make ~code:diagnostic_code
    ~message:
      (Printf.sprintf "%s: metadata %s failed [%s]: %s" path
         (operation_string value.operation) value.code value.message)
    ()
