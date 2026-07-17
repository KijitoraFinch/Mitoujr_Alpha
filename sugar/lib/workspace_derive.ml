let ( let* ) = Result.bind

let command_result ?summary ?(diagnostics = []) ?(patches = [])
    ?(artifacts = []) ~termination ~effect () =
  match
    Command_result.make ~command:"derive" ~termination ~effect ~diagnostics
      ~patches ~artifacts ?summary ()
  with
  | Ok result -> result
  | Error message -> invalid_arg ("invalid derive CommandResult: " ^ message)

let usage message =
  command_result ~termination:(Command_result.Usage_failure message)
    ~effect:Command_result.No_change
    ~summary:[ ("message", Command_result.Text message) ] ()

let internal operation =
  command_result
    ~termination:(Command_result.Internal_failure "internal operation failed")
    ~effect:Command_result.No_change
    ~summary:
      [
        ("errorCode", Command_result.Text "filesystem-io");
        ("operation", Command_result.Text operation);
      ]
    ()

let sidecar_path primary =
  match List.rev (Workspace_path.segments primary) with
  | [] -> invalid_arg "workspace path has no segments"
  | basename :: reversed_parent ->
      let stem =
        match String.rindex_opt basename '.' with
        | Some index when index > 0 -> String.sub basename 0 index
        | _ -> basename
      in
      Workspace_path.of_segments
        (List.rev reversed_parent @ [ stem ^ ".annotations.yaml" ])

let has_inline annotation =
  List.exists
    (function Annotation.Markdown_inline _ -> true | _ -> false)
    (Annotation.materialization annotation)

let has_sidecar annotation =
  List.exists
    (function Annotation.Sidecar _ -> true | _ -> false)
    (Annotation.materialization annotation)

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

let render_annotation ~primary_path annotation =
  let local =
    Annotation.id annotation |> Annotation_id.local |> Identifier.to_string
  in
  let* subject =
    match Annotation.subject annotation with
    | Annotation.Region (Region_ref.Resolved id) -> Ok id
    | Annotation.Region (Region_ref.Address _) ->
        Error "inline annotation subject must be a resolved region"
  in
  let* reference =
    match Annotation.object_ annotation with
    | Annotation.Reference_object id -> Ok id
    | Annotation.Region_object _ | Annotation.Literal _ ->
        Error "inline-to-sidecar derive currently requires a reference object"
  in
  let subject_local = Region_id.local subject |> Identifier.to_string in
  let reference_local = Reference_id.local reference |> Identifier.to_string in
  let path = Workspace_path.to_canonical_string primary_path in
  Ok
    (String.concat "\n"
       [
         "  " ^ yaml_quote local ^ ":";
         "    subject:";
         "      artifact:";
         "        origin:";
         "          kind: workspace";
         "          path: " ^ yaml_quote path;
         "      selector:";
         "        kind: region-id";
         "        id: " ^ yaml_quote subject_local;
         "      interpreter: markdown";
         "    predicate: " ^ yaml_quote (Annotation.predicate annotation);
         "    object:";
         "      ref: " ^ yaml_quote reference_local;
       ])

let render_annotations ~primary_path annotations =
  annotations
  |> List.sort (fun left right ->
         Annotation_id.compare (Annotation.id left) (Annotation.id right))
  |> List.fold_left
       (fun result annotation ->
         let* rendered = result in
         let* entry = render_annotation ~primary_path annotation in
         Ok (entry :: rendered))
       (Ok [])
  |> Result.map (fun reversed -> "\n" ^ String.concat "\n\n" (List.rev reversed) ^ "\n")

let invalid_sidecar artifacts artifact_id message =
  let diagnostic =
    Diagnostic.make ~code:Diagnostic.Invalid_sidecar ~message
      ~location:
        {
          Diagnostic.artifact = Some artifact_id;
          region = None;
          annotation = None;
          range = None;
        }
      ()
    |> Result.get_ok
  in
  command_result ~termination:Command_result.Completed
    ~effect:Command_result.No_change ~artifacts ~diagnostics:[ diagnostic ]
    ~summary:[ ("patches", Command_result.Count 0) ] ()

let patch ~primary_path ~sidecar_path ~sidecar_file annotations =
  let content = Workspace_read.content sidecar_file in
  let* offset = Sidecar_edit.annotation_insertion_offset content in
  let* replacement = render_annotations ~primary_path annotations in
  let range = Text_range.make ~start:offset ~end_:offset |> Result.get_ok in
  let edit = Text_edit.make ~range ~replacement |> Result.get_ok in
  let resulting_content =
    String.sub content 0 offset ^ replacement
    ^ String.sub content offset (String.length content - offset)
  in
  let patch_hash = Content_digest.of_content replacement |> Content_digest.to_hex in
  let* id = Patch_id.make ("patch:derive-sidecar:" ^ String.sub patch_hash 0 24) in
  let* provenance = Provenance.make ~source:"derive:inline-to-sidecar" () in
  Proposed_patch.make ~id ~target:sidecar_path
    ~expected_identity:(Workspace_read.content_identity sidecar_file)
    ~resulting_identity:(Content_identity.of_content resulting_content)
    ~edits:[ edit ] ~reason:"materialize inline annotations in the sidecar"
    ~provenance

let derive_sidecar ~workspace ~artifact =
  let inspected = Workspace_inspect.inspect ~workspace ~artifact in
  match Command_result.termination inspected with
  | Command_result.Usage_failure message -> usage message
  | Command_result.Internal_failure _ -> internal "inspect-artifact"
  | Command_result.Completed ->
      let artifacts = Command_result.artifacts inspected in
      if Command_result.diagnostics inspected <> [] then
        command_result ~termination:Command_result.Completed
          ~effect:Command_result.No_change ~artifacts
          ~diagnostics:(Command_result.diagnostics inspected)
          ~summary:[ ("patches", Command_result.Count 0) ] ()
      else
        let candidates =
          Command_result.annotations inspected
          |> List.filter (fun annotation ->
                 has_inline annotation && not (has_sidecar annotation))
        in
        if candidates = [] then
          command_result ~termination:Command_result.Completed
            ~effect:Command_result.No_change ~artifacts
            ~summary:[ ("patches", Command_result.Count 0) ] ()
        else
          let sidecar_path = Result.get_ok (sidecar_path artifact) in
          match Workspace_read.read ~workspace ~path:sidecar_path with
          | Error Workspace_read.Missing_artifact ->
              invalid_sidecar artifacts (Artifact.id (List.hd artifacts))
                "inline-to-sidecar derive requires an existing sidecar"
          | Error _ -> internal "read-sidecar"
          | Ok sidecar_file -> (
              match patch ~primary_path:artifact ~sidecar_path ~sidecar_file candidates with
              | Error message ->
                  let sidecar_id =
                    Artifact_id.make
                      ("artifact:" ^ Workspace_path.to_canonical_string sidecar_path)
                    |> Result.get_ok
                  in
                  invalid_sidecar artifacts sidecar_id message
              | Ok patch ->
                  command_result ~termination:Command_result.Completed
                    ~effect:Command_result.Patches_proposed ~artifacts
                    ~patches:[ patch ]
                    ~summary:[ ("patches", Command_result.Count 1) ] ())
