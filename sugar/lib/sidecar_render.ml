let ( let* ) = Result.bind

let yaml_quote value =
  let output = Buffer.create (String.length value + 2) in
  Buffer.add_char output '"';
  String.iter
    (fun char ->
      match char with
      | '"' -> Buffer.add_string output "\\\""
      | '\\' -> Buffer.add_string output "\\\\"
      | '\n' -> Buffer.add_string output "\\n"
      | '\r' -> Buffer.add_string output "\\r"
      | '\t' -> Buffer.add_string output "\\t"
      | '\b' -> Buffer.add_string output "\\b"
      | '\012' -> Buffer.add_string output "\\f"
      | char when Char.code char < 0x20 || Char.code char = 0x7f ->
          Buffer.add_string output (Printf.sprintf "\\x%02X" (Char.code char))
      | char -> Buffer.add_char output char)
    value;
  Buffer.add_char output '"';
  Buffer.contents output

let indentation width = String.make width ' '
let line width value = indentation width ^ value

let literal = function
  | Selector.Literal.String value -> yaml_quote value
  | Selector.Literal.Int value -> string_of_int value
  | Selector.Literal.Bool value -> string_of_bool value

let json_scalar = function
  | `Null -> Some "null"
  | `Bool value -> Some (string_of_bool value)
  | `Int value -> Some (string_of_int value)
  | `String value -> Some (yaml_quote value)
  | `Intlit _ | `Float _ | `Tuple _ | `Variant _ | `List _ | `Assoc _ ->
      None

let rec json_lines ~indent value =
  match json_scalar value with
  | Some value -> [ line indent value ]
  | None -> (
      match value with
      | `List [] -> [ line indent "[]" ]
      | `List values ->
          List.concat_map
            (fun value ->
              match json_scalar value with
              | Some value -> [ line indent ("- " ^ value) ]
              | None -> line indent "-" :: json_lines ~indent:(indent + 2) value)
            values
      | `Assoc [] -> [ line indent "{}" ]
      | `Assoc fields ->
          List.concat_map
            (fun (name, value) ->
              match json_scalar value with
              | Some value ->
                  [ line indent (yaml_quote name ^ ": " ^ value) ]
              | None ->
                  line indent (yaml_quote name ^ ":")
                  :: json_lines ~indent:(indent + 2) value)
            fields
      | `Null | `Bool _ | `Int _ | `String _ -> assert false
      | `Intlit _ | `Float _ | `Tuple _ | `Variant _ -> assert false)

let schema_value_lines ~indent ~item kind value =
  let prefix = if item then "- " else "" in
  let child = indent + if item then 4 else 2 in
  [
    line indent (prefix ^ kind ^ ":");
    line child
      ("schema: " ^ yaml_quote (Schema_value.schema value));
    line child "value:";
  ]
  @ json_lines ~indent:(child + 2)
      (Schema_value.value value |> Normalized_value.to_yojson)

let expectation_lines ~indent ~item expectation =
  let prefix value = if item then "- " ^ value else value in
  let child = indent + if item then 4 else 2 in
  match expectation with
  | Expectation.Observation_identity identity ->
      [
        line indent (prefix "observationIdentity:");
        line child "observationType:";
        line (child + 2)
          ("name: "
          ^ yaml_quote
              (Observation_identity.observation_type identity
              |> Observation_type.name));
        line (child + 2)
          ("version: "
          ^ yaml_quote
              (Observation_identity.observation_type identity
              |> Observation_type.version));
        line child ("key: " ^ yaml_quote (Observation_identity.key identity));
      ]
  | Expectation.Content_identity identity ->
      [
        line indent (prefix "contentIdentity:");
        line child
          ("hash: " ^ yaml_quote (Content_identity.display_hash identity));
        line child
          ("size: " ^ string_of_int (Content_identity.byte_length identity));
      ]
  | Expectation.Revision revision ->
      schema_value_lines ~indent ~item "revision" revision
  | Expectation.Fingerprint fingerprint ->
      schema_value_lines ~indent ~item "fingerprint" fingerprint

let selector_lines ~indent selector =
  match selector with
  | Selector.Whole_observation ->
      Ok [ line indent "selector:"; line (indent + 2) "kind: whole-observation" ]
  | Selector.Region_id id ->
      Ok
        [
          line indent "selector:";
          line (indent + 2) "kind: region-id";
          line (indent + 2)
            ("id: " ^ yaml_quote (Identifier.to_string id));
        ]
  | Selector.Row_filter filter ->
      let conditions =
        Selector.Row_filter.conditions filter
        |> List.map (fun (field, value) ->
               line (indent + 4)
                 (yaml_quote (Selector.Field_name.to_string field)
                 ^ ": " ^ literal value))
      in
      Ok
        ([
           line indent "selector:";
           line (indent + 2) "kind: row-filter";
           line (indent + 2) "where:";
         ]
        @ conditions)
  | Selector.Text_range range ->
      Ok
        [
          line indent "selector:";
          line (indent + 2) "kind: text-range";
          line (indent + 2) ("start: " ^ string_of_int (Text_range.start range));
          line (indent + 2) ("end: " ^ string_of_int (Text_range.end_ range));
        ]
  | Selector.Extension extension ->
      Ok
        ([
           line indent "selector:";
           line (indent + 2) "kind: extension";
           line (indent + 2)
             ("schema: " ^ yaml_quote (Selector.Extension.schema extension));
           line (indent + 2) "value:";
         ]
        @ json_lines ~indent:(indent + 4) (Selector.Extension.value extension))

let origin_lines ~indent = function
  | Origin.Workspace path ->
      [
        line indent "kind: workspace";
        line indent
          ("path: " ^ yaml_quote (Workspace_path.to_canonical_string path));
      ]
  | Origin.Git { repo; rev; path } ->
      [ line indent "kind: git"; line indent ("repo: " ^ yaml_quote repo) ]
      @
      (match rev with
      | None -> []
      | Some rev -> [ line indent ("rev: " ^ yaml_quote rev) ])
      @ [ line indent ("path: " ^ yaml_quote path) ]
  | Origin.Web url ->
      [ line indent "kind: web"; line indent ("url: " ^ yaml_quote url) ]
  | Origin.Generated name ->
      [ line indent "kind: generated"; line indent ("name: " ^ yaml_quote name) ]
  | Origin.External uri ->
      [ line indent "kind: external"; line indent ("uri: " ^ yaml_quote uri) ]
  | Origin.Extension { observer; locator } ->
      [
        line indent "kind: extension";
        line indent "observer:";
        line (indent + 2)
          ("name: " ^ yaml_quote (Resource_observer.name observer));
        line (indent + 2)
          ("version: " ^ yaml_quote (Resource_observer.version observer));
        line indent "locator:";
      ]
      @ json_lines ~indent:(indent + 2)
          (Normalized_value.to_yojson locator)

let address_lines ~indent address =
  let* selector =
    selector_lines ~indent (Region_address.selector address)
  in
  let* interpreter =
    match
      ( Region_address.interpreter address,
        Region_address.interpreter_version address )
    with
    | None, None -> Ok []
    | Some name, Some version ->
        Ok
          [
            line indent ("interpreter: " ^ yaml_quote name);
            line indent ("interpreterVersion: " ^ yaml_quote version);
          ]
    | _ -> Error "sidecar address has an incomplete interpreter identity"
  in
  let expectation =
    match Region_address.expectation address with
    | None -> []
    | Some expectation ->
        line indent "expectation:"
        :: expectation_lines ~indent:(indent + 2) ~item:false expectation
  in
  Ok
    ([ line indent "origin:" ]
    @ origin_lines ~indent:(indent + 2) (Region_address.origin address)
    @ selector @ interpreter @ expectation)

let binding = function
  | Reference.Pinned -> "pinned"
  | Reference.Tracking -> "tracking"
  | Reference.Floating -> "floating"

let reference_lines reference =
  let local =
    Reference.id reference |> Reference_id.local |> Identifier.to_string
  in
  let* target = address_lines ~indent:8 (Reference.target reference) in
  let expectations =
    match Reference.expectations reference with
    | [] -> []
    | values ->
        line 6 "expect:"
        :: List.concat_map
             (expectation_lines ~indent:8 ~item:true)
             values
  in
  Ok
    ([ line 4 (yaml_quote local ^ ":"); line 6 "target:" ]
    @ target
    @ [
        line 6 "binding:";
        line 8 ("mode: " ^ binding (Reference.binding reference));
      ]
    @ expectations)

let region_ref_address ~primary_path = function
  | Region_ref.Address address -> Ok address
  | Region_ref.Resolved id ->
      Region_address.make ~origin:(Observation.workspace primary_path)
        ~selector:(Selector.Region_id (Region_id.local id))
        ~interpreter:"markdown" ~interpreter_version:"1" ()

let annotation_lines ~primary_path annotation =
  let local =
    Annotation.id annotation |> Annotation_id.local |> Identifier.to_string
  in
  let* subject =
    region_ref_address ~primary_path (Annotation.subject annotation)
  in
  let* subject = address_lines ~indent:8 subject in
  let* object_lines =
    match Annotation.object_ annotation with
    | Annotation.Reference_object reference ->
        Ok
          [
            line 6 "object:";
            line 8
              ("ref: "
              ^ yaml_quote
                  (reference |> Reference_id.local |> Identifier.to_string));
          ]
    | Annotation.Region_object region ->
        let* address = region_ref_address ~primary_path region in
        let* address = address_lines ~indent:10 address in
        Ok (line 6 "object:" :: line 8 "region:" :: address)
    | Annotation.Literal value ->
        Ok [ line 6 "object:"; line 8 ("literal: " ^ yaml_quote value) ]
  in
  Ok
    ([ line 4 (yaml_quote local ^ ":"); line 6 "subject:" ]
    @ subject
    @ [
        line 6
          ("predicate: " ^ yaml_quote (Annotation.predicate annotation));
      ]
    @ object_lines)

let render_entries ~compare render values =
  values
  |> List.sort compare
  |> List.fold_left
       (fun result value ->
         let* groups = result in
         let* lines = render value in
         Ok (lines :: groups))
       (Ok [])
  |> Result.map (fun reversed -> List.rev reversed |> List.concat)

let derived_section ~primary_path ~references ~annotations =
  let* reference_lines =
    render_entries
      ~compare:(fun left right ->
        Reference_id.compare (Reference.id left) (Reference.id right))
      reference_lines references
  in
  let* annotation_lines =
    render_entries
      ~compare:(fun left right ->
        Annotation_id.compare (Annotation.id left) (Annotation.id right))
      (annotation_lines ~primary_path) annotations
  in
  let refs =
    if reference_lines = [] then [ line 2 "refs: {}" ]
    else line 2 "refs:" :: reference_lines
  in
  let annotations =
    if annotation_lines = [] then [ line 2 "annotations: {}" ]
    else line 2 "annotations:" :: annotation_lines
  in
  Ok (String.concat "\n" ([ "derived:" ] @ refs @ annotations) ^ "\n")

let new_document ~primary_path ~references ~annotations =
  let* derived = derived_section ~primary_path ~references ~annotations in
  Ok
    ("version: 2\nscope:\n  origin:\n    kind: workspace\n    path: "
    ^ yaml_quote (Workspace_path.to_canonical_string primary_path)
    ^ "\nauthored:\n  refs: {}\n  annotations: {}\n" ^ derived)
