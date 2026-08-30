open Monika_sugar

let get = function Ok value -> value | Error message -> failwith message

let () =
  let observation_id = get (Observation_id.make "observation:docs/note") in
  let path = get (Workspace_path.of_segments [ "docs"; "note.md" ]) in
  let content = "# Title\n\nSee source.\n" in
  let observation =
    Observation.of_bytes ~id:observation_id
      ~origin:(Observation.workspace path)
      ~observation_type:
        (get (Observation_type.make ~name:"text/markdown" ~version:"1" ()))
      ~bytes:content
  in
  let heading_range = get (Text_range.make ~start:0 ~end_:7) in
  let region_id = get (Region_id.make ~observation:observation_id ~local:"heading") in
  let markdown = get (Interpreter.make ~name:"markdown" ~version:"1" ()) in
  let region =
    get
      (Region.make ~id:region_id
         ~observation_identity:(Observation.identity observation)
         ~selector:(Selector.Text_range heading_range) ~interpreter:markdown
         ~summary:"Title" ~range:heading_range
         ~fingerprint:"sha256:region-title" ())
  in
  let target_selector =
    Selector.Region_id (get (Identifier.make "source-definition"))
  in
  let target =
    get
      (Region_address.make ~origin:(Observation.workspace path)
         ~selector:target_selector ~interpreter:"markdown"
         ~interpreter_version:"1" ())
  in
  let reference_id =
    get
      (Reference_id.make ~scope:(Observation.workspace path)
         ~local:"source-reference")
  in
  let reference =
    Reference.make ~id:reference_id ~target ~binding:Reference.Tracking
      ~expectations:[ Expectation.Digest (Content_digest.of_content "source") ]
      ()
  in
  let annotation_id =
    get
      (Annotation_id.make ~scope:(Observation.workspace path)
         ~local:"title-annotation")
  in
  let annotation =
    get
      (Annotation.make ~id:annotation_id
         ~subject:(Region_ref.Resolved region_id)
         ~predicate:"display-title" ~object_:(Annotation.Literal "Title")
      )
  in
  let encoding =
    get (Observation_encoding.make ~name:"markdown-inline" ~version:"1")
  in
  let source =
    Source_location.in_observation ~observation:observation_id
      ~locator:(Source_location.Byte_range heading_range) ~encoding
  in
  let reference_definition =
    Reference_definition_occurrence.make ~reference ~source
  in
  let annotation_occurrence =
    Annotation_occurrence.make ~annotation ~source
  in
  let result =
    get
      (Command_result.make ~command:"inspect"
         ~termination:Command_result.Completed ~effect:Command_result.No_change
         ~observations:[ observation ] ~regions:[ region ] ~references:[ reference ]
         ~annotations:[ annotation ] ~reference_definitions:[ reference_definition ]
         ~annotation_occurrences:[ annotation_occurrence ]
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
