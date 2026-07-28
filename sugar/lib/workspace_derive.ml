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

let annotation_local annotation =
  Annotation.id annotation |> Annotation_id.local |> Identifier.to_string

let reference_local reference =
  Reference.id reference |> Reference_id.local |> Identifier.to_string

let add_missing ~local existing additions =
  existing
  @ List.filter
      (fun addition ->
        not
          (List.exists
             (fun current -> String.equal (local current) (local addition))
             existing))
      additions

let required_reference_ids annotations =
  List.filter_map
    (fun annotation ->
      match Annotation.object_ annotation with
      | Annotation.Reference_object id -> Some id
      | Annotation.Region_object _ | Annotation.Literal _ -> None)
    annotations

let select_references references ids =
  List.filter
    (fun reference ->
      List.exists
        (fun id -> Reference_id.equal id (Reference.id reference))
        ids)
    references

let markdown_observations ~workspace ~artifact ~artifact_id =
  let* file =
    match Workspace_read.read ~workspace ~path:artifact with
    | Ok file -> Ok file
    | Error _ -> Error "read-primary"
  in
  Markdown_inspect.inspect ~artifact:artifact_id ~path:artifact
    (Workspace_read.content file)
  |> Result.map_error (fun _ -> "inspect-primary")

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

let patch ~primary_path ~sidecar_path ~sidecar_file ~references ~annotations =
  let content = Workspace_read.content sidecar_file in
  let* replacement =
    Sidecar_render.derived_section ~primary_path ~references ~annotations
  in
  let* existing = Sidecar_edit.optional_derived_section_range content in
  let* range, replacement =
    match existing with
    | Some range -> Ok (range, replacement)
    | None ->
        let* offset = Sidecar_edit.derived_insertion_offset content in
        let prefix =
          if offset = 0 || content.[offset - 1] = '\n' then "" else "\n"
        in
        Ok
          ( Text_range.make ~start:offset ~end_:offset |> Result.get_ok,
            prefix ^ replacement )
  in
  let edit = Text_edit.make ~range ~replacement |> Result.get_ok in
  let start = Text_range.start range in
  let end_ = Text_range.end_ range in
  let resulting_content =
    String.sub content 0 start ^ replacement
    ^ String.sub content end_ (String.length content - end_)
  in
  let patch_identity =
    String.concat "\000"
      [
        "inline-to-sidecar";
        "1";
        "edit";
        Workspace_path.to_canonical_string sidecar_path;
        (let identity = Workspace_read.content_identity sidecar_file in
         Content_identity.display_hash identity ^ ":"
         ^ string_of_int (Content_identity.byte_length identity));
        replacement;
        (let identity = Content_identity.of_content resulting_content in
         Content_identity.display_hash identity ^ ":"
         ^ string_of_int (Content_identity.byte_length identity));
      ]
  in
  let patch_hash =
    Content_digest.of_content patch_identity |> Content_digest.to_hex
  in
  let* id = Patch_id.make ("patch:derive-sidecar:" ^ String.sub patch_hash 0 24) in
  let* provenance = Provenance.make ~source:"derive:inline-to-sidecar" () in
  Proposed_patch.make ~id ~target:sidecar_path
    ~expected_identity:(Workspace_read.content_identity sidecar_file)
    ~resulting_identity:(Content_identity.of_content resulting_content)
    ~edits:[ edit ] ~reason:"materialize inline annotations in the sidecar"
    ~provenance

let create_patch ~primary_path ~sidecar_path ~references ~annotations =
  let* content =
    Sidecar_render.new_document ~primary_path ~references ~annotations
  in
  let resulting_identity = Content_identity.of_content content in
  let patch_identity =
    String.concat "\000"
      [
        "inline-to-sidecar";
        "1";
        "create";
        Workspace_path.to_canonical_string sidecar_path;
        content;
        Content_identity.display_hash resulting_identity;
        string_of_int (Content_identity.byte_length resulting_identity);
      ]
  in
  let patch_hash =
    Content_digest.of_content patch_identity |> Content_digest.to_hex
  in
  let* id =
    Patch_id.make ("patch:derive-sidecar:" ^ String.sub patch_hash 0 24)
  in
  let* provenance = Provenance.make ~source:"derive:inline-to-sidecar" () in
  Proposed_patch.make_create ~id ~target:sidecar_path ~resulting_identity
    ~content ~reason:"create the derived sidecar materialization" ~provenance

let derive_sidecar ~workspace ~artifact =
  let inspected = Workspace_inspect.inspect ~workspace ~artifact in
  match Command_result.termination inspected with
  | Command_result.Usage_failure message -> usage message
  | Command_result.Internal_failure _ -> internal "inspect-artifact"
  | Command_result.Completed ->
      let artifacts = Command_result.artifacts inspected in
      let blocking_diagnostics =
        Command_result.diagnostics inspected
        |> List.filter (fun diagnostic ->
               Diagnostic.effective_severity diagnostic = Diagnostic.Error)
      in
      if blocking_diagnostics <> [] then
        command_result ~termination:Command_result.Completed
          ~effect:Command_result.No_change ~artifacts
          ~diagnostics:(Command_result.diagnostics inspected)
          ~summary:[ ("patches", Command_result.Count 0) ] ()
      else
        let primary_id = Artifact.id (List.hd artifacts) in
        match markdown_observations ~workspace ~artifact ~artifact_id:primary_id with
        | Error operation -> internal operation
        | Ok markdown ->
            let sidecar_path = Result.get_ok (sidecar_path artifact) in
            match Workspace_read.read ~workspace ~path:sidecar_path with
            | Error Workspace_read.Missing_artifact ->
                let candidates = markdown.annotations in
                let references =
                  required_reference_ids candidates
                  |> select_references markdown.references
                in
                if candidates = [] then
                  command_result ~termination:Command_result.Completed
                    ~effect:Command_result.No_change ~artifacts
                    ~diagnostics:(Command_result.diagnostics inspected)
                    ~summary:[ ("patches", Command_result.Count 0) ] ()
                else (
                  match
                    create_patch ~primary_path:artifact ~sidecar_path
                      ~references ~annotations:candidates
                  with
                  | Error _ -> internal "construct-sidecar-create-patch"
                  | Ok patch ->
                      command_result ~termination:Command_result.Completed
                        ~effect:Command_result.Patches_proposed ~artifacts
                        ~diagnostics:(Command_result.diagnostics inspected)
                        ~patches:[ patch ]
                        ~summary:[ ("patches", Command_result.Count 1) ] ())
            | Error _ -> internal "read-sidecar"
            | Ok sidecar_file ->
                let sidecar_id =
                  Artifact_id.make
                    ("artifact:"
                    ^ Workspace_path.to_canonical_string sidecar_path)
                  |> Result.get_ok
                in
                (match
                   Sidecar_v1.decode ~primary_artifact:primary_id
                     ~sidecar_artifact:sidecar_id ~sidecar_path
                     (Workspace_read.content sidecar_file)
                 with
                | Error message -> invalid_sidecar artifacts sidecar_id message
                | Ok sidecar ->
                    let candidates =
                      List.filter
                        (fun annotation ->
                          has_inline annotation
                          && not
                               (List.exists
                                  (fun existing ->
                                    String.equal
                                      (annotation_local existing)
                                      (annotation_local annotation))
                                  sidecar.annotations))
                        markdown.annotations
                    in
                    let needed =
                      required_reference_ids candidates
                      |> select_references markdown.references
                      |> List.filter (fun reference ->
                             not
                               (List.exists
                                  (fun existing ->
                                    String.equal
                                      (reference_local existing)
                                      (reference_local reference))
                                  sidecar.references))
                    in
                    let references =
                      add_missing ~local:reference_local
                        sidecar.derived.references needed
                    in
                    let annotations =
                      add_missing ~local:annotation_local
                        sidecar.derived.annotations candidates
                    in
                    if candidates = [] && references = sidecar.derived.references
                    then
                      command_result ~termination:Command_result.Completed
                        ~effect:Command_result.No_change ~artifacts
                        ~diagnostics:(Command_result.diagnostics inspected)
                        ~summary:[ ("patches", Command_result.Count 0) ] ()
                    else
                      match
                        patch ~primary_path:artifact ~sidecar_path ~sidecar_file
                          ~references ~annotations
                      with
                      | Error message ->
                          invalid_sidecar artifacts sidecar_id message
                      | Ok patch ->
                          command_result
                            ~termination:Command_result.Completed
                            ~effect:Command_result.Patches_proposed ~artifacts
                            ~diagnostics:(Command_result.diagnostics inspected)
                            ~patches:[ patch ]
                            ~summary:
                              [ ("patches", Command_result.Count 1) ]
                            ())
