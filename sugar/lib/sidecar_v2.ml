type section = {
  references : Reference_definition_occurrence.t list;
  annotations : Annotation_occurrence.t list;
}

let ( let* ) = Result.bind

let at path message = Error (path ^ ": " ^ message)

let rec validate_node path = function
  | `Alias _ -> at path "aliases are not allowed"
  | `Scalar scalar ->
      if scalar.Yaml.anchor <> None then at path "anchors are not allowed"
      else if scalar.tag <> None then at path "explicit tags are not allowed"
      else if not (Utf8.is_valid scalar.value) then
        at path "scalar must be valid UTF-8"
      else Ok ()
  | `A sequence ->
      if sequence.Yaml.s_anchor <> None then at path "anchors are not allowed"
      else if sequence.s_tag <> None then at path "explicit tags are not allowed"
      else
        List.mapi
          (fun index node -> validate_node (Printf.sprintf "%s[%d]" path index) node)
          sequence.s_members
        |> List.fold_left
             (fun result validation -> let* () = result in validation)
             (Ok ())
  | `O mapping ->
      if mapping.Yaml.m_anchor <> None then at path "anchors are not allowed"
      else if mapping.m_tag <> None then at path "explicit tags are not allowed"
      else
        List.mapi
          (fun index (key, value) ->
            let* () = validate_node (Printf.sprintf "%s.<key:%d>" path index) key in
            validate_node (Printf.sprintf "%s.<value:%d>" path index) value)
          mapping.m_members
        |> List.fold_left
             (fun result validation -> let* () = result in validation)
             (Ok ())

let scalar path = function
  | `Scalar value -> Ok value
  | _ -> at path "expected a scalar"

let string path node =
  let* value = scalar path node in
  if String.length value.Yaml.value = 0 then at path "must not be empty"
  else Ok value.value

let mapping path = function
  | `O mapping ->
      let rec loop seen acc = function
        | [] -> Ok (List.rev acc)
        | (key, value) :: rest ->
            let* key = string (path ^ ".<key>") key in
            if List.mem key seen then at (path ^ "." ^ key) "duplicate key"
            else loop (key :: seen) ((key, value) :: acc) rest
      in
      loop [] [] mapping.Yaml.m_members
  | _ -> at path "expected a mapping"

let sequence path = function
  | `A sequence -> Ok sequence.Yaml.s_members
  | _ -> at path "expected a sequence"

let fields path ~required ~optional node =
  let* members = mapping path node in
  let allowed = required @ optional in
  let rec reject_unknown = function
    | [] -> Ok ()
    | (name, _) :: _ when not (List.mem name allowed) ->
        at (path ^ "." ^ name) "unknown field"
    | _ :: rest -> reject_unknown rest
  in
  let* () = reject_unknown members in
  let rec require = function
    | [] -> Ok ()
    | name :: rest ->
        if List.mem_assoc name members then require rest
        else at (path ^ "." ^ name) "missing required field"
  in
  let* () = require required in
  Ok members

let field members name = List.assoc name members
let optional_field members name = List.assoc_opt name members

let yaml_scalar_json path scalar =
  match scalar.Yaml.style with
  | `Single_quoted | `Double_quoted | `Literal | `Folded ->
      Ok (`String scalar.value)
  | `Any | `Plain -> (
      match scalar.value with
      | "true" -> Ok (`Bool true)
      | "false" -> Ok (`Bool false)
      | "null" | "Null" | "NULL" | "~" -> Ok `Null
      | value -> (
          match int_of_string_opt value with
          | Some integer when Protocol_integer.is_safe integer -> Ok (`Int integer)
          | Some _ -> at path "integer is outside the protocol-safe range"
          | None -> Ok (`String value)))

let rec yaml_json path = function
  | `Alias _ -> at path "aliases are not allowed"
  | `Scalar scalar -> yaml_scalar_json path scalar
  | `A sequence ->
      List.mapi
        (fun index item -> yaml_json (Printf.sprintf "%s[%d]" path index) item)
        sequence.Yaml.s_members
      |> List.fold_left
           (fun result item ->
             let* values = result in
             let* value = item in
             Ok (value :: values))
           (Ok [])
      |> Result.map (fun values -> `List (List.rev values))
  | `O _ as node ->
      let* members = mapping path node in
      List.fold_left
        (fun result (name, node) ->
          let* fields = result in
          let* value = yaml_json (path ^ "." ^ name) node in
          Ok ((name, value) :: fields))
        (Ok []) members
      |> Result.map (fun fields -> `Assoc (List.rev fields))

let parse_origin path node =
  let* members = mapping path node in
  let* kind_node =
    match List.assoc_opt "kind" members with
    | Some value -> Ok value
    | None -> at (path ^ ".kind") "missing required field"
  in
  let* kind = string (path ^ ".kind") kind_node in
  let exact required optional = fields path ~required ~optional node in
  match kind with
  | "workspace" ->
      let* fields = exact [ "kind"; "path" ] [] in
      let* encoded = string (path ^ ".path") (field fields "path") in
      Workspace_path.of_canonical_string encoded
      |> Result.map Observation.workspace
      |> Result.map_error (fun message -> path ^ ".path: " ^ message)
  | "git" ->
      let* fields = exact [ "kind"; "repo"; "path" ] [ "rev" ] in
      let* repo = string (path ^ ".repo") (field fields "repo") in
      let* origin_path = string (path ^ ".path") (field fields "path") in
      let* rev =
        match optional_field fields "rev" with
        | None -> Ok None
        | Some node -> string (path ^ ".rev") node |> Result.map Option.some
      in
      Origin.git ~repo ?rev ~path:origin_path ()
      |> Result.map_error (fun message -> path ^ ": " ^ message)
  | "web" ->
      let* fields = exact [ "kind"; "url" ] [] in
      let* value = string (path ^ ".url") (field fields "url") in
      Origin.web value |> Result.map_error (fun message -> path ^ ": " ^ message)
  | "generated" ->
      let* fields = exact [ "kind"; "name" ] [] in
      let* value = string (path ^ ".name") (field fields "name") in
      Origin.generated value
      |> Result.map_error (fun message -> path ^ ": " ^ message)
  | "external" ->
      let* fields = exact [ "kind"; "uri" ] [] in
      let* value = string (path ^ ".uri") (field fields "uri") in
      Origin.external_ value
      |> Result.map_error (fun message -> path ^ ": " ^ message)
  | "extension" ->
      let* origin_fields = exact [ "kind"; "observer"; "locator" ] [] in
      let* observer_fields =
        fields (path ^ ".observer") ~required:[ "name"; "version" ] ~optional:[]
          (field origin_fields "observer")
      in
      let* name = string (path ^ ".observer.name") (field observer_fields "name") in
      let* version =
        string (path ^ ".observer.version") (field observer_fields "version")
      in
      let* observer =
        Resource_observer.make ~name ~version ()
        |> Result.map_error (fun message -> path ^ ".observer: " ^ message)
      in
      let* locator =
        yaml_json (path ^ ".locator") (field origin_fields "locator")
      in
      Origin.extension ~observer ~locator ()
      |> Result.map_error (fun message -> path ^ ": " ^ message)
  | _ -> at (path ^ ".kind") "unsupported origin kind"

let decimal_integer value =
  let length = String.length value in
  let first_digit = if length > 0 && value.[0] = '-' then 1 else 0 in
  length > first_digit
  &&
  let rec loop index =
    index = length
    ||
    match value.[index] with
    | '0' .. '9' -> loop (index + 1)
    | _ -> false
  in
  loop first_digit

let decimal_float value =
  let length = String.length value in
  let start = if length > 0 && value.[0] = '-' then 1 else 0 in
  let rec digits index =
    if index < length then
      match value.[index] with '0' .. '9' -> digits (index + 1) | _ -> index
    else index
  in
  let integer_end = digits start in
  if integer_end = start then false
  else
    let fraction_end =
      if integer_end < length && value.[integer_end] = '.' then
        let ending = digits (integer_end + 1) in
        if ending = integer_end + 1 then None else Some ending
      else Some integer_end
    in
    match fraction_end with
    | None -> false
    | Some ending ->
        if ending = length then integer_end < length
        else if value.[ending] = 'e' || value.[ending] = 'E' then
          let exponent_start =
            if ending + 1 < length
               && (value.[ending + 1] = '+' || value.[ending + 1] = '-')
            then ending + 2
            else ending + 1
          in
          exponent_start < length && digits exponent_start = length
        else false

let selector_literal path node =
  let* scalar = scalar path node in
  match scalar.Yaml.style with
  | `Single_quoted | `Double_quoted | `Literal | `Folded ->
      Ok (Selector.Literal.String scalar.value)
  | `Any | `Plain -> (
      match scalar.value with
      | "true" -> Ok (Selector.Literal.Bool true)
      | "false" -> Ok (Selector.Literal.Bool false)
      | "null" | "Null" | "NULL" | "~" -> at path "null is not allowed"
      | value when decimal_integer value -> (
          match int_of_string_opt value with
          | Some integer when Protocol_integer.is_safe integer ->
              Ok (Selector.Literal.Int integer)
          | Some _ -> at path "integer is outside the protocol-safe range"
          | None -> at path "integer is outside the implementation range")
      | value when decimal_float value ->
          at path "floating-point values are not allowed"
      | value -> Ok (Selector.Literal.String value))

let parse_selector path node =
  let* members = mapping path node in
  let* kind_node =
    match List.assoc_opt "kind" members with
    | Some value -> Ok value
    | None -> at (path ^ ".kind") "missing required field"
  in
  let* kind = string (path ^ ".kind") kind_node in
  let exact required optional = fields path ~required ~optional node in
  match kind with
  | "whole-observation" ->
      let* _ = exact [ "kind" ] [] in
      Ok Selector.Whole_observation
  | "region-id" ->
      let* members = exact [ "kind"; "id" ] [] in
      let* id = string (path ^ ".id") (field members "id") in
      Identifier.make id
      |> Result.map (fun id -> Selector.Region_id id)
      |> Result.map_error (fun message -> path ^ ".id: " ^ message)
  | "text-range" ->
      let* members = exact [ "kind"; "start"; "end" ] [] in
      let integer name =
        let* scalar = scalar (path ^ "." ^ name) (field members name) in
        match int_of_string_opt scalar.Yaml.value with
        | Some value when Protocol_integer.is_nonnegative_safe value -> Ok value
        | Some _ -> at (path ^ "." ^ name) "must be a non-negative safe integer"
        | None -> at (path ^ "." ^ name) "must be an integer"
      in
      let* start = integer "start" in
      let* end_ = integer "end" in
      Text_range.make ~start ~end_
      |> Result.map (fun range -> Selector.Text_range range)
      |> Result.map_error (fun message -> path ^ ": " ^ message)
  | "row-filter" ->
      let* members = exact [ "kind"; "where" ] [] in
      let* conditions = mapping (path ^ ".where") (field members "where") in
      let* conditions =
        List.map
          (fun (name, value) ->
            let value_path = Printf.sprintf "%s.where.%s" path name in
            let* name =
              Selector.Field_name.make name
              |> Result.map_error (fun message -> value_path ^ ": " ^ message)
            in
            let* value = selector_literal value_path value in
            Ok (name, value))
          conditions
        |> List.fold_left
             (fun result item ->
               let* acc = result in
               let* item = item in
               Ok (item :: acc))
             (Ok [])
        |> Result.map List.rev
      in
      Selector.Row_filter.make conditions
      |> Result.map (fun filter -> Selector.Row_filter filter)
      |> Result.map_error (fun message -> path ^ ".where: " ^ message)
  | "extension" ->
      let* members = exact [ "kind"; "schema"; "value" ] [] in
      let* schema = string (path ^ ".schema") (field members "schema") in
      let* value = yaml_json (path ^ ".value") (field members "value") in
      Selector.Extension.make ~schema ~value
      |> Result.map (fun value -> Selector.Extension value)
      |> Result.map_error (fun message -> path ^ ": " ^ message)
  | _ -> at (path ^ ".kind") "unsupported selector kind"

let parse_expectation path node =
  let* members =
    fields path ~required:[]
      ~optional:
        [
          "observationIdentity";
          "contentIdentity";
          "revision";
          "fingerprint";
        ]
      node
  in
  match members with
  | [ ("observationIdentity", value) ] ->
      let* value = yaml_json (path ^ ".observationIdentity") value in
      Normal_decode.observation_identity value
      |> Result.map (fun identity -> Expectation.Observation_identity identity)
      |> Result.map_error (fun message -> path ^ ": " ^ message)
  | [ ("contentIdentity", value) ] ->
      let* value = yaml_json (path ^ ".contentIdentity") value in
      Normal_decode.content_identity value
      |> Result.map (fun identity -> Expectation.Content_identity identity)
      |> Result.map_error (fun message -> path ^ ": " ^ message)
  | [ (("revision" | "fingerprint") as kind, value) ] ->
      let* value_fields =
        fields (path ^ "." ^ kind) ~required:[ "schema"; "value" ]
          ~optional:[] value
      in
      let* schema =
        string (path ^ "." ^ kind ^ ".schema")
          (field value_fields "schema")
      in
      let* value =
        yaml_json (path ^ "." ^ kind ^ ".value")
          (field value_fields "value")
      in
      let* value =
        Schema_value.make ~schema ~value ()
        |> Result.map_error (fun message -> path ^ ": " ^ message)
      in
      if String.equal kind "revision" then Ok (Expectation.Revision value)
      else Ok (Expectation.Fingerprint value)
  | [] -> at path "one expectation field is required"
  | _ -> at path "expectation fields are mutually exclusive"

let parse_address path node =
  let* members =
    fields path ~required:[ "origin"; "selector" ]
      ~optional:[ "interpreter"; "interpreterVersion"; "expectation" ] node
  in
  let* origin =
    parse_origin (path ^ ".origin") (field members "origin")
  in
  let* selector = parse_selector (path ^ ".selector") (field members "selector") in
  let* interpreter =
    match optional_field members "interpreter" with
    | None -> Ok None
    | Some node -> string (path ^ ".interpreter") node |> Result.map Option.some
  in
  let* interpreter_version =
    match optional_field members "interpreterVersion" with
    | None -> Ok None
    | Some node ->
        string (path ^ ".interpreterVersion") node |> Result.map Option.some
  in
  let* expectation =
    match optional_field members "expectation" with
    | None -> Ok None
    | Some node ->
        parse_expectation (path ^ ".expectation") node |> Result.map Option.some
  in
  Region_address.make ~origin ~selector ?interpreter ?interpreter_version
    ?expectation ()
  |> Result.map_error (fun message -> path ^ ": " ^ message)

let parse_expectations path node =
  let* items = sequence path node in
  List.mapi
    (fun index node ->
      let item_path = Printf.sprintf "%s[%d]" path index in
      parse_expectation item_path node)
    items
  |> List.fold_left
       (fun result item ->
         let* acc = result in
         let* item = item in
         Ok (item :: acc))
       (Ok [])
  |> Result.map List.rev

let parse_binding path node =
  let* members = fields path ~required:[ "mode" ] ~optional:[] node in
  let* mode = string (path ^ ".mode") (field members "mode") in
  match mode with
  | "pinned" -> Ok Reference.Pinned
  | "tracking" -> Ok Reference.Tracking
  | "floating" -> Ok Reference.Floating
  | _ -> at (path ^ ".mode") "unsupported binding mode"

let source_location ~snapshot ~section ~collection ~name =
  let* locator =
    Structured_location.make ~schema:"monika.sidecar.yaml-path@1"
      ~value:
        (`List
          [ `String section; `String collection; `String name ])
  in
  let ownership =
    if String.equal section "authored" then Source_location.Authored
    else Source_location.Derived
  in
  Ok
    (Source_location.in_sidecar ~path:(Sidecar_snapshot.path snapshot)
       ~content_identity:(Sidecar_snapshot.content_identity snapshot) ~locator
       ~ownership)

let parse_reference ~scope ~snapshot ~section name node =
  let path = "$." ^ section ^ ".refs." ^ name in
  let* members =
    fields path ~required:[ "target"; "binding" ] ~optional:[ "expect" ] node
  in
  let* id =
    Reference_id.make ~scope ~local:name
    |> Result.map_error (fun message -> path ^ ": " ^ message)
  in
  let* target = parse_address (path ^ ".target") (field members "target") in
  let* binding = parse_binding (path ^ ".binding") (field members "binding") in
  let* expectations =
    match optional_field members "expect" with
    | None -> Ok []
    | Some node -> parse_expectations (path ^ ".expect") node
  in
  let* reference =
    Reference.make ~id ~target ~binding ~expectations ()
    |> Result.map_error (fun message -> path ^ ": " ^ message)
  in
  let* source =
    source_location ~snapshot ~section ~collection:"refs" ~name
  in
  Ok (Reference_definition_occurrence.make ~reference ~source)

let parse_annotation_object ~scope path node =
  let* members =
    fields path ~required:[] ~optional:[ "ref"; "region"; "literal" ] node
  in
  match
    ( optional_field members "ref",
      optional_field members "region",
      optional_field members "literal" )
  with
  | Some reference, None, None ->
      let* local = string (path ^ ".ref") reference in
      Reference_id.make ~scope ~local
      |> Result.map (fun id -> Annotation.Reference_object id)
      |> Result.map_error (fun message -> path ^ ".ref: " ^ message)
  | None, Some region, None ->
      parse_address (path ^ ".region") region
      |> Result.map (fun address ->
             Annotation.Region_object (Region_ref.Address address))
  | None, None, Some literal ->
      let* scalar = scalar (path ^ ".literal") literal in
      Ok (Annotation.Literal scalar.Yaml.value)
  | None, None, None -> at path "one object variant is required"
  | _ -> at path "object variants are mutually exclusive"

let parse_annotation ~scope ~snapshot ~section name node =
  let path = "$." ^ section ^ ".annotations." ^ name in
  let* members =
    fields path ~required:[ "subject"; "predicate"; "object" ] ~optional:[] node
  in
  let* id =
    Annotation_id.make ~scope ~local:name
    |> Result.map_error (fun message -> path ^ ": " ^ message)
  in
  let* subject = parse_address (path ^ ".subject") (field members "subject") in
  let* predicate = string (path ^ ".predicate") (field members "predicate") in
  let* object_ =
    parse_annotation_object ~scope (path ^ ".object") (field members "object")
  in
  let* annotation =
    Annotation.make ~id ~subject:(Region_ref.Address subject) ~predicate ~object_
  in
  let* source =
    source_location ~snapshot ~section ~collection:"annotations" ~name
  in
  Ok (Annotation_occurrence.make ~annotation ~source)

let decode_named_map path parse node =
  let* members = mapping path node in
  List.fold_left
    (fun result (name, node) ->
      let* acc = result in
      let* value = parse name node in
      Ok (value :: acc))
    (Ok []) members
  |> Result.map List.rev

let decode_section ~scope ~snapshot name node =
  let path = "$." ^ name in
  let* members =
    fields path ~required:[ "refs"; "annotations" ] ~optional:[] node
  in
  let* references =
    decode_named_map (path ^ ".refs")
      (parse_reference ~scope ~snapshot ~section:name)
      (field members "refs")
  in
  let* annotations =
    decode_named_map (path ^ ".annotations")
      (parse_annotation ~scope ~snapshot ~section:name)
      (field members "annotations")
  in
  Ok { references; annotations }
let decode snapshot =
  let content = Sidecar_snapshot.bytes snapshot in
  if not (Utf8.is_valid content) then Error "$: sidecar must be valid UTF-8"
  else
    let* () =
      Sidecar_edit.validate_layout_profile content
      |> Result.map_error (fun message -> "$: invalid layout: " ^ message)
    in
    let* document =
      Yaml.yaml_of_string content
      |> Result.map_error (fun (`Msg message) -> "$: invalid YAML: " ^ message)
    in
    let* () = validate_node "$" document in
    let* root =
      fields "$" ~required:[ "version"; "scope"; "authored"; "derived" ]
        ~optional:[] document
    in
    let* version = string "$.version" (field root "version") in
    if not (String.equal version "2") then Error "$.version: unsupported sidecar version"
    else
      let* scope_fields =
        fields "$.scope" ~required:[ "origin" ] ~optional:[]
          (field root "scope")
      in
      let* scope =
        parse_origin "$.scope.origin" (field scope_fields "origin")
      in
      let* derived =
        decode_section ~scope ~snapshot "derived" (field root "derived")
      in
      let* authored =
        decode_section ~scope ~snapshot "authored" (field root "authored")
      in
      Ok
        (Sidecar_contents.make ~scope
           ~annotations:(authored.annotations @ derived.annotations)
           ~reference_definitions:(authored.references @ derived.references))
