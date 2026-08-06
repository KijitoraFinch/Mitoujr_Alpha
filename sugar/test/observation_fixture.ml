open Monika_sugar

let get = function Ok value -> value | Error message -> failwith message

let () =
  let artifact_id = get (Artifact_id.make "artifact:docs/note") in
  let path = get (Workspace_path.of_segments [ "docs"; "note.md" ]) in
  let content = "# Title\n\nSee source.\n" in
  let artifact =
    get
      (Artifact.make ~id:artifact_id ~origin:(Artifact.workspace path)
         ~media_type:"text/markdown"
         ~content_identity:(Content_identity.of_content content) ())
  in
  let heading_range = get (Text_range.make ~start:0 ~end_:7) in
  let region_id = get (Region_id.make ~artifact:artifact_id ~local:"heading") in
  let markdown = get (Interpreter.make ~name:"markdown" ~version:"1" ()) in
  let region =
    get
      (Region.make ~id:region_id
         ~observation_identity:(Artifact.observation_identity artifact)
         ~selector:(Selector.Text_range heading_range) ~interpreter:markdown
         ~summary:"Title" ~range:heading_range
         ~fingerprint:"sha256:region-title" ())
  in
  let target_selector =
    Selector.Region_id (get (Identifier.make "source-definition"))
  in
  let target =
    get
      (Region_address.make ~artifact:(Artifact.workspace path)
         ~selector:target_selector ~interpreter:"markdown" ())
  in
  let reference_id =
    get (Reference_id.make ~artifact:artifact_id ~local:"source-reference")
  in
  let provenance = get (Provenance.make ~source:"markdown-inline" ()) in
  let reference =
    Reference.make ~id:reference_id ~target ~binding:Reference.Tracking
      ~expectations:[ Expectation.Digest (Content_digest.of_content "source") ]
      ~provenance:[ provenance ] ()
  in
  let annotation_id =
    get (Annotation_id.make ~artifact:artifact_id ~local:"title-annotation")
  in
  let annotation =
    get
      (Annotation.make ~id:annotation_id
         ~subject:(Annotation.Region (Region_ref.Resolved region_id))
         ~predicate:"display-title" ~object_:(Annotation.Literal "Title")
         ~provenance:[ provenance ]
         ~materialization:
           [ Annotation.Markdown_inline { artifact = artifact_id; range = heading_range } ])
  in
  let result =
    get
      (Command_result.make ~command:"inspect"
         ~termination:Command_result.Completed ~effect:Command_result.No_change
         ~artifacts:[ artifact ] ~regions:[ region ] ~references:[ reference ]
         ~annotations:[ annotation ]
         ~summary:
           [
             ("annotations", Command_result.Count 1);
             ("references", Command_result.Count 1);
             ("regions", Command_result.Count 1);
           ]
         ())
  in
  result |> Normal.Command_result.normalize |> Normal_json.command_result
  |> Yojson.Safe.pretty_to_channel stdout;
  print_newline ()
