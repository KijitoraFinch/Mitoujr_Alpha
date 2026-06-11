open Monika_sugar

let get = function Ok value -> value | Error message -> failwith message

let () =
  let target = get (Workspace_path.of_segments [ "notes"; "title.txt" ]) in
  let initial = get (Workspace_snapshot.make [ (target, "Title\n") ]) in
  let patch_id = get (Identifier.make "patch:title") in
  let range = get (Text_range.make ~start:0 ~end_:5) in
  let before = Content_identity.of_content "Title\n" in
  let after = Content_identity.of_content "Heading\n" in
  let provenance = get (Provenance.make ~source:"transition-fixture" ()) in
  let patch =
    get
      (Proposed_patch.make ~id:patch_id ~target ~expected_identity:before
         ~resulting_identity:after
         ~edits:[ Text_edit.make ~range ~replacement:"Heading" ]
         ~reason:"Normalize the title" ~provenance)
  in
  let final_snapshot, changed =
    match Workspace_ops.apply_patch initial patch with
    | Workspace_ops.Applied value -> (value.snapshot, value.changed)
    | Workspace_ops.No_change _ -> failwith "fixture patch unexpectedly did nothing"
    | Workspace_ops.Conflict _ -> failwith "fixture patch unexpectedly conflicted"
  in
  let result =
    get
      (Command_result.make ~command:"apply"
         ~termination:Command_result.Completed ~effect:Command_result.Applied
         ~patches:[ patch ] ~changed_artifacts:[ changed ]
         ~summary:[ ("applied", Command_result.Count 1) ] ())
  in
  let normalized_result = Normal.Command_result.normalize result in
  let json =
    `Assoc
      [
        ("schemaVersion", `String "1");
        ("caseId", `String "apply-title-replacement");
        ( "initialSnapshot",
          initial |> Normal.Workspace_snapshot.normalize
          |> Normal_json.workspace_snapshot );
        ( "command",
          `Assoc
            [
              ("name", `String "apply");
              ("patch", patch |> Normal.Patch.normalize |> Normal_json.patch);
            ] );
        ("result", Normal_json.command_result normalized_result);
        ( "finalSnapshot",
          final_snapshot |> Normal.Workspace_snapshot.normalize
          |> Normal_json.workspace_snapshot );
        ("exitClass", `String normalized_result.exit_class);
      ]
  in
  Yojson.Safe.pretty_to_channel stdout json;
  print_newline ()
