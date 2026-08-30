type t = {
  protocol_version : string;
  capability : Capability.t;
}

let supported_protocol_version = "1"
let ( let* ) = Result.bind

let object_fields label = function
  | `Assoc fields -> Ok fields
  | _ -> Error (label ^ " must be an object")

let validate_fields ~label ~required ~optional fields =
  let allowed = required @ optional in
  let names = List.map fst fields in
  let sorted = List.sort String.compare names in
  let rec has_duplicate = function
    | left :: (right :: _ as rest) ->
        String.equal left right || has_duplicate rest
    | [] | [ _ ] -> false
  in
  if not (List.for_all Utf8.is_valid names) then
    Error (label ^ " has an invalid UTF-8 field name")
  else
  match List.find_opt (fun name -> not (List.mem name allowed)) names with
  | Some name -> Error (label ^ " has unknown field: " ^ name)
  | None when has_duplicate sorted -> Error (label ^ " has duplicate fields")
  | None -> (
      match List.find_opt (fun name -> not (List.mem_assoc name fields)) required with
      | Some name -> Error (label ^ " is missing field: " ^ name)
      | None -> Ok fields)

let string label = function
  | `String value when Utf8.is_valid value -> Ok value
  | `String _ -> Error (label ^ " must be valid UTF-8")
  | _ -> Error (label ^ " must be a string")

let string_list label = function
  | `List values ->
      let rec loop index accumulated = function
        | [] -> Ok (List.rev accumulated)
        | value :: rest ->
            let* value = string (Printf.sprintf "%s[%d]" label index) value in
            loop (index + 1) (value :: accumulated) rest
      in
      loop 0 [] values
  | _ -> Error (label ^ " must be an array")

let kind = function
  | "resource-observer" -> Ok Capability.Resource_observer
  | "interpreter" -> Ok Capability.Interpreter
  | "annotation-extractor" -> Ok Capability.Annotation_extractor
  | "reference-extractor" -> Ok Capability.Reference_extractor
  | "deriver" -> Ok Capability.Deriver
  | "auditor" -> Ok Capability.Auditor
  | "renderer" -> Ok Capability.Renderer
  | "indexer" -> Ok Capability.Indexer
  | value -> Error ("capability.type is unsupported: " ^ value)

let decode_applies_to json =
  let* fields = object_fields "capability.appliesTo" json in
  let* fields =
    validate_fields ~label:"capability.appliesTo"
      ~required:[ "mediaTypes"; "pathGlobs" ] ~optional:[] fields
  in
  let* media_types =
    string_list "capability.appliesTo.mediaTypes"
      (List.assoc "mediaTypes" fields)
  in
  let* path_globs =
    string_list "capability.appliesTo.pathGlobs"
      (List.assoc "pathGlobs" fields)
  in
  Ok Capability.{ media_types; path_globs }

let decode_schemas json =
  let* fields = object_fields "capability.schemas" json in
  let* fields =
    validate_fields ~label:"capability.schemas" ~required:[]
      ~optional:[ "selector" ] fields
  in
  let optional_string name =
    match List.assoc_opt name fields with
    | None -> Ok None
    | Some value ->
        let* value = string ("capability.schemas." ^ name) value in
        Ok (Some value)
  in
  let* selector = optional_string "selector" in
  Ok Capability.{ selector; annotation = None; options = None }

let decode_capability json =
  let* fields = object_fields "capability" json in
  let* fields =
    validate_fields ~label:"capability"
      ~required:[ "type"; "name"; "version" ]
      ~optional:[ "appliesTo"; "schemas" ] fields
  in
  let* kind_name = string "capability.type" (List.assoc "type" fields) in
  let* kind = kind kind_name in
  let* name = string "capability.name" (List.assoc "name" fields) in
  let* version = string "capability.version" (List.assoc "version" fields) in
  let* applies_to =
    match List.assoc_opt "appliesTo" fields with
    | None -> Ok None
    | Some value -> Result.map Option.some (decode_applies_to value)
  in
  let* schemas =
    match List.assoc_opt "schemas" fields with
    | None -> Ok None
    | Some value -> Result.map Option.some (decode_schemas value)
  in
  Capability.make ~kind ~name ~version ?applies_to ?schemas ()

let of_yojson json =
  let* fields = object_fields "extension manifest" json in
  let* fields =
    validate_fields ~label:"extension manifest"
      ~required:[ "protocolVersion"; "capability" ] ~optional:[] fields
  in
  let* protocol_version =
    string "extension manifest.protocolVersion"
      (List.assoc "protocolVersion" fields)
  in
  if not (String.equal protocol_version supported_protocol_version) then
    Error ("unsupported extension protocol version: " ^ protocol_version)
  else
    let* capability = decode_capability (List.assoc "capability" fields) in
    Ok { protocol_version; capability }

let protocol_version value = value.protocol_version
let capability value = value.capability

let equal_applies_to left right =
  match (left, right) with
  | None, None -> true
  | Some (left : Capability.applies_to), Some (right : Capability.applies_to) ->
      List.equal String.equal
        (List.sort String.compare left.media_types)
        (List.sort String.compare right.media_types)
      && List.equal String.equal
           (List.sort String.compare left.path_globs)
           (List.sort String.compare right.path_globs)
  | None, Some _ | Some _, None -> false

let equal_schemas left right =
  match (left, right) with
  | None, None -> true
  | Some (left : Capability.schemas), Some (right : Capability.schemas) ->
      Option.equal String.equal left.selector right.selector
      && Option.equal String.equal left.annotation right.annotation
      && Option.equal String.equal left.options right.options
  | None, Some _ | Some _, None -> false

let equal left right =
  String.equal left.protocol_version right.protocol_version
  && Capability.compare left.capability right.capability = 0
  && equal_applies_to
       (Capability.applies_to left.capability)
       (Capability.applies_to right.capability)
  && equal_schemas
       (Capability.schemas left.capability)
       (Capability.schemas right.capability)
