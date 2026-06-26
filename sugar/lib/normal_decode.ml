let ( let* ) = Result.bind
let ( let+ ) value f = Result.map f value

let error path message = Error (path ^ ": " ^ message)

let type_name = function
  | `Assoc _ -> "object"
  | `Bool _ -> "boolean"
  | `Float _ -> "float"
  | `Int _ -> "integer"
  | `Intlit _ -> "integer literal"
  | `List _ -> "array"
  | `Null -> "null"
  | `String _ -> "string"
  | `Tuple _ -> "tuple"
  | `Variant _ -> "variant"

let field_path path name = path ^ "." ^ name
let index_path path index = path ^ "[" ^ string_of_int index ^ "]"

let duplicate_name fields =
  let names = List.map fst fields |> List.sort String.compare in
  let rec loop = function
    | left :: (right :: _ as rest) ->
        if String.equal left right then Some left else loop rest
    | _ -> None
  in
  loop names

let object_fields path allowed = function
  | `Assoc fields -> (
      match duplicate_name fields with
      | Some name -> error path ("duplicate field: " ^ name)
      | None -> (
          match
            List.find_opt
              (fun (name, _) -> not (List.mem name allowed))
              fields
          with
          | Some (name, _) -> error path ("unknown field: " ^ name)
          | None -> Ok fields))
  | json -> error path ("expected object, got " ^ type_name json)

let require fields path name =
  match List.assoc_opt name fields with
  | Some value -> Ok value
  | None -> error path ("missing field: " ^ name)

let optional fields name = List.assoc_opt name fields

let string path = function
  | `String value -> Ok value
  | json -> error path ("expected string, got " ^ type_name json)

let int path = function
  | `Int value -> Ok value
  | json -> error path ("expected integer, got " ^ type_name json)

let list path decode = function
  | `List values ->
      let rec loop index acc = function
        | [] -> Ok (List.rev acc)
        | value :: rest ->
            let* decoded = decode (index_path path index) value in
            loop (index + 1) (decoded :: acc) rest
      in
      loop 0 [] values
  | json -> error path ("expected array, got " ^ type_name json)

let bind_construct path = function
  | Ok value -> Ok value
  | Error message -> error path message

let workspace_path_at path json =
  let* value = string path json in
  Workspace_path.of_canonical_string value |> bind_construct path

let content_identity_at path json =
  let* fields = object_fields path [ "hash"; "size" ] json in
  let* hash = require fields path "hash" in
  let* hash = string (field_path path "hash") hash in
  let* size = require fields path "size" in
  let* size = int (field_path path "size") size in
  let prefix = "sha256:" in
  let prefix_length = String.length prefix in
  if
    String.length hash <= prefix_length
    || not (String.equal (String.sub hash 0 prefix_length) prefix)
  then
    error (field_path path "hash")
      "content identity hash must start with sha256:"
  else
    let sha256 =
      String.sub hash prefix_length (String.length hash - prefix_length)
    in
    Content_identity.make ~sha256 ~byte_length:size |> bind_construct path

let text_range_at path json =
  let* fields = object_fields path [ "start"; "end" ] json in
  let* start = require fields path "start" in
  let* start = int (field_path path "start") start in
  let* end_ = require fields path "end" in
  let* end_ = int (field_path path "end") end_ in
  Text_range.make ~start ~end_ |> bind_construct path

let text_edit_at path json =
  let* fields = object_fields path [ "range"; "replacement" ] json in
  let* range = require fields path "range" in
  let* range = text_range_at (field_path path "range") range in
  let* replacement = require fields path "replacement" in
  let+ replacement = string (field_path path "replacement") replacement in
  Text_edit.make ~range ~replacement

let provenance_at path json =
  let* fields = object_fields path [ "source"; "detail" ] json in
  let* source = require fields path "source" in
  let* source = string (field_path path "source") source in
  let* detail =
    match optional fields "detail" with
    | None -> Ok None
    | Some value ->
        let+ detail = string (field_path path "detail") value in
        Some detail
  in
  Provenance.make ~source ?detail () |> bind_construct path

let proposed_patch_at path json =
  let* fields =
    object_fields path
      [
        "id";
        "target";
        "expectedContentIdentity";
        "resultingContentIdentity";
        "edits";
        "reason";
        "provenance";
      ]
      json
  in
  let* id = require fields path "id" in
  let* id = string (field_path path "id") id in
  let* id = Identifier.make id |> bind_construct (field_path path "id") in
  let* target = require fields path "target" in
  let* target = workspace_path_at (field_path path "target") target in
  let* expected_identity = require fields path "expectedContentIdentity" in
  let* expected_identity =
    content_identity_at (field_path path "expectedContentIdentity")
      expected_identity
  in
  let* resulting_identity = require fields path "resultingContentIdentity" in
  let* resulting_identity =
    content_identity_at
      (field_path path "resultingContentIdentity")
      resulting_identity
  in
  let* edits = require fields path "edits" in
  let* edits = list (field_path path "edits") text_edit_at edits in
  let* reason = require fields path "reason" in
  let* reason = string (field_path path "reason") reason in
  let* provenance = require fields path "provenance" in
  let* provenance = provenance_at (field_path path "provenance") provenance in
  Proposed_patch.make ~id ~target ~expected_identity ~resulting_identity
    ~edits ~reason ~provenance
  |> bind_construct path

let workspace_path json = workspace_path_at "$" json
let content_identity json = content_identity_at "$" json
let text_range json = text_range_at "$" json
let text_edit json = text_edit_at "$" json
let provenance json = provenance_at "$" json
let proposed_patch json = proposed_patch_at "$" json
