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

let selector_lines ~indent selector =
  match selector with
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
  | Selector.Whole_artifact
  | Selector.Text_range _
  | Selector.Extension _ ->
      Error "sidecar v1 cannot render this selector kind"

let address_lines ~indent address =
  let* path =
    match Region_address.artifact address with
    | Origin.Workspace path -> Ok path
    | _ -> Error "sidecar v1 can render only workspace origins"
  in
  let* selector =
    selector_lines ~indent (Region_address.selector address)
  in
  let interpreter =
    match Region_address.interpreter address with
    | None -> []
    | Some value ->
        [ line indent ("interpreter: " ^ yaml_quote value) ]
  in
  Ok
    ([
       line indent "artifact:";
       line (indent + 2) "origin:";
       line (indent + 4) "kind: workspace";
       line (indent + 4)
         ("path: " ^ yaml_quote (Workspace_path.to_canonical_string path));
     ]
    @ selector @ interpreter)

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
        :: List.map
             (function
               | Expectation.Digest digest ->
                   line 8
                     ("- digest: sha256:" ^ Content_digest.to_hex digest))
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

let subject_address ~primary_path annotation =
  match Annotation.subject annotation with
  | Annotation.Region (Region_ref.Address address) -> Ok address
  | Annotation.Region (Region_ref.Resolved id) ->
      Region_address.make ~artifact:(Artifact.workspace primary_path)
        ~selector:(Selector.Region_id (Region_id.local id))
        ~interpreter:"markdown" ()

let annotation_lines ~primary_path annotation =
  let local =
    Annotation.id annotation |> Annotation_id.local |> Identifier.to_string
  in
  let* subject = subject_address ~primary_path annotation in
  let* subject = address_lines ~indent:8 subject in
  let* reference =
    match Annotation.object_ annotation with
    | Annotation.Reference_object id -> Ok id
    | Annotation.Region_object _ | Annotation.Literal _ ->
        Error "sidecar v1 derived annotations require a reference object"
  in
  Ok
    ([ line 4 (yaml_quote local ^ ":"); line 6 "subject:" ]
    @ subject
    @ [
        line 6
          ("predicate: " ^ yaml_quote (Annotation.predicate annotation));
        line 6 "object:";
        line 8
          ("ref: "
          ^ yaml_quote
              (reference |> Reference_id.local |> Identifier.to_string));
      ])

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
    ("version: 1\n" ^ derived
   ^ "authored:\n  refs: {}\n  annotations: {}\n")
