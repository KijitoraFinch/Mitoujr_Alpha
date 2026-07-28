type section = {
  references : Reference.t list;
  annotations : Annotation.t list;
}

type override_kind = Reference_override | Annotation_override

type override = {
  kind : override_kind;
  local : string;
}

type t = {
  derived : section;
  authored : section;
  references : Reference.t list;
  annotations : Annotation.t list;
  overrides : override list;
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

let parse_workspace_origin path node =
  let* artifact = fields path ~required:[ "origin" ] ~optional:[] node in
  let origin_path = path ^ ".origin" in
  let* origin =
    fields origin_path ~required:[ "kind"; "path" ] ~optional:[]
      (field artifact "origin")
  in
  let* kind = string (origin_path ^ ".kind") (field origin "kind") in
  if not (String.equal kind "workspace") then
    at (origin_path ^ ".kind") "only workspace origins are supported"
  else
    let* encoded = string (origin_path ^ ".path") (field origin "path") in
    let* workspace_path =
      Workspace_path.of_canonical_string encoded
      |> Result.map_error (fun message -> origin_path ^ ".path: " ^ message)
    in
    Ok (Artifact.workspace workspace_path)

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
  let* members = fields path ~required:[ "kind" ] ~optional:[ "id"; "where" ] node in
  let* kind = string (path ^ ".kind") (field members "kind") in
  match kind with
  | "region-id" ->
      if optional_field members "where" <> None then at path "where is not valid for region-id"
      else
        let* id_node =
          match optional_field members "id" with
          | Some node -> Ok node
          | None -> at (path ^ ".id") "missing required field"
        in
        let* id = string (path ^ ".id") id_node in
        Identifier.make id
        |> Result.map (fun id -> Selector.Region_id id)
        |> Result.map_error (fun message -> path ^ ".id: " ^ message)
  | "row-filter" ->
      if optional_field members "id" <> None then at path "id is not valid for row-filter"
      else
        let* where_node =
          match optional_field members "where" with
          | Some node -> Ok node
          | None -> at (path ^ ".where") "missing required field"
        in
        let* conditions = mapping (path ^ ".where") where_node in
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
  | _ -> at (path ^ ".kind") "unsupported selector kind"

let parse_address path node =
  let* members =
    fields path ~required:[ "artifact"; "selector" ]
      ~optional:[ "interpreter" ] node
  in
  let* artifact = parse_workspace_origin (path ^ ".artifact") (field members "artifact") in
  let* selector = parse_selector (path ^ ".selector") (field members "selector") in
  let* interpreter =
    match optional_field members "interpreter" with
    | None -> Ok None
    | Some node -> string (path ^ ".interpreter") node |> Result.map Option.some
  in
  Region_address.make ~artifact ~selector ?interpreter ()
  |> Result.map_error (fun message -> path ^ ": " ^ message)

let parse_digest path node =
  let* value = string path node in
  let prefix = "sha256:" in
  if String.length value <> String.length prefix + 64
     || String.sub value 0 (String.length prefix) <> prefix
  then at path "expected a sha256 digest"
  else
    Content_digest.of_hex
      (String.sub value (String.length prefix) 64)
    |> Result.map (fun digest -> Expectation.Digest digest)
    |> Result.map_error (fun message -> path ^ ": " ^ message)

let parse_expectations path node =
  let* items = sequence path node in
  List.mapi
    (fun index node ->
      let item_path = Printf.sprintf "%s[%d]" path index in
      let* members = fields item_path ~required:[ "digest" ] ~optional:[] node in
      parse_digest (item_path ^ ".digest") (field members "digest"))
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

let provenance sidecar_path section =
  Provenance.make ~source:"sidecar"
    ~detail:
      (Workspace_path.to_canonical_string sidecar_path ^ "#" ^ section)
    ()

let parse_reference ~primary_artifact ~sidecar_path ~section name node =
  let path = "$." ^ section ^ ".refs." ^ name in
  let* members =
    fields path ~required:[ "target"; "binding" ] ~optional:[ "expect" ] node
  in
  let* id =
    Reference_id.make ~artifact:primary_artifact ~local:name
    |> Result.map_error (fun message -> path ^ ": " ^ message)
  in
  let* target = parse_address (path ^ ".target") (field members "target") in
  let* binding = parse_binding (path ^ ".binding") (field members "binding") in
  let* expectations =
    match optional_field members "expect" with
    | None -> Ok []
    | Some node -> parse_expectations (path ^ ".expect") node
  in
  let* provenance = provenance sidecar_path section in
  Ok
    (Reference.make ~id ~target ~binding ~expectations
       ~provenance:[ provenance ] ())

let parse_annotation ~primary_artifact ~sidecar_artifact ~sidecar_path ~section
    name node =
  let path = "$." ^ section ^ ".annotations." ^ name in
  let* members =
    fields path ~required:[ "subject"; "predicate"; "object" ] ~optional:[] node
  in
  let* id =
    Annotation_id.make ~artifact:primary_artifact ~local:name
    |> Result.map_error (fun message -> path ^ ": " ^ message)
  in
  let* subject = parse_address (path ^ ".subject") (field members "subject") in
  let* predicate = string (path ^ ".predicate") (field members "predicate") in
  let* object_members =
    fields (path ^ ".object") ~required:[ "ref" ] ~optional:[]
      (field members "object")
  in
  let* reference_name =
    string (path ^ ".object.ref") (field object_members "ref")
  in
  let* reference =
    Reference_id.make ~artifact:primary_artifact ~local:reference_name
    |> Result.map_error (fun message -> path ^ ".object.ref: " ^ message)
  in
  let* provenance = provenance sidecar_path section in
  Annotation.make ~id ~subject:(Annotation.Region (Region_ref.Address subject))
    ~predicate ~object_:(Annotation.Reference_object reference)
    ~provenance:[ provenance ]
    ~materialization:
      [ Annotation.Sidecar { artifact = sidecar_artifact; path = Some sidecar_path } ]

let decode_named_map path parse node =
  let* members = mapping path node in
  List.fold_left
    (fun result (name, node) ->
      let* acc = result in
      let* value = parse name node in
      Ok (value :: acc))
    (Ok []) members
  |> Result.map List.rev

let empty_section = { references = []; annotations = [] }

let decode_section ~primary_artifact ~sidecar_artifact ~sidecar_path name node =
  let path = "$." ^ name in
  let* members =
    fields path ~required:[] ~optional:[ "refs"; "annotations" ] node
  in
  let* references =
    match optional_field members "refs" with
    | None -> Ok []
    | Some refs ->
        decode_named_map (path ^ ".refs")
          (parse_reference ~primary_artifact ~sidecar_path ~section:name)
          refs
  in
  let* annotations =
    match optional_field members "annotations" with
    | None -> Ok []
    | Some annotations ->
        decode_named_map (path ^ ".annotations")
          (parse_annotation ~primary_artifact ~sidecar_artifact ~sidecar_path
             ~section:name)
          annotations
  in
  Ok { references; annotations }

let binding_equal left right =
  match (left, right) with
  | Reference.Pinned, Reference.Pinned
  | Reference.Tracking, Reference.Tracking
  | Reference.Floating, Reference.Floating ->
      true
  | _ -> false

let reference_equal left right =
  Reference.compare_target (Reference.target left) (Reference.target right) = 0
  && binding_equal (Reference.binding left) (Reference.binding right)
  && List.compare Expectation.compare
       (Reference.expectations left)
       (Reference.expectations right)
     = 0

let annotation_equal left right =
  Region_ref.compare
    (match Annotation.subject left with Annotation.Region subject -> subject)
    (match Annotation.subject right with Annotation.Region subject -> subject)
  = 0
  && String.equal (Annotation.predicate left) (Annotation.predicate right)
  &&
  match (Annotation.object_ left, Annotation.object_ right) with
  | Annotation.Reference_object left, Annotation.Reference_object right ->
      Reference_id.equal left right
  | Annotation.Region_object left, Annotation.Region_object right ->
      Region_ref.compare left right = 0
  | Annotation.Literal left, Annotation.Literal right -> String.equal left right
  | _ -> false

let merge_owned_entries ~id ~equal ~override_kind derived authored =
  let overridden =
    List.filter_map
      (fun authored_entry ->
        match
          List.find_opt
            (fun derived_entry -> id derived_entry = id authored_entry)
            derived
        with
        | Some derived_entry when not (equal derived_entry authored_entry) ->
            Some { kind = override_kind; local = id authored_entry }
        | Some _ | None -> None)
      authored
  in
  let effective =
    List.filter
      (fun derived_entry ->
        not
          (List.exists
             (fun authored_entry -> id authored_entry = id derived_entry)
             authored))
      derived
    @ authored
  in
  (effective, overridden)

let reference_local reference =
  Reference.id reference |> Reference_id.local |> Identifier.to_string

let annotation_local annotation =
  Annotation.id annotation |> Annotation_id.local |> Identifier.to_string

let decode ~primary_artifact ~sidecar_artifact ~sidecar_path content =
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
      fields "$" ~required:[ "version" ]
        ~optional:[ "derived"; "authored" ] document
    in
    let* version = string "$.version" (field root "version") in
    if not (String.equal version "1") then Error "$.version: unsupported sidecar version"
    else
      let* derived =
        match optional_field root "derived" with
        | None -> Ok empty_section
        | Some node ->
            decode_section ~primary_artifact ~sidecar_artifact ~sidecar_path
              "derived" node
      in
      let* authored =
        match optional_field root "authored" with
        | None -> Ok empty_section
        | Some node ->
            decode_section ~primary_artifact ~sidecar_artifact ~sidecar_path
              "authored" node
      in
      let references, reference_overrides =
        merge_owned_entries ~id:reference_local ~equal:reference_equal
          ~override_kind:Reference_override derived.references
          authored.references
      in
      let annotations, annotation_overrides =
        merge_owned_entries ~id:annotation_local ~equal:annotation_equal
          ~override_kind:Annotation_override derived.annotations
          authored.annotations
      in
      Ok
        {
          derived;
          authored;
          references;
          annotations;
          overrides = reference_overrides @ annotation_overrides;
        }
