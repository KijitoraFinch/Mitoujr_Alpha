open Monika_sugar

let get = function Ok value -> value | Error message -> failwith message

let () =
  let patch_id = get (Identifier.make "patch:readme-title") in
  let target = get (Workspace_path.of_segments [ "docs"; "README \255.md" ]) in
  let edit_range = get (Text_range.make ~start:0 ~end_:5) in
  let provenance =
    get
      (Provenance.make ~source:"markdown-inline"
         ~detail:"annotation:readme-title" ())
  in
  let before = Content_identity.of_content "Title\n" in
  let after = Content_identity.of_content "Heading\n" in
  let patch =
    get
      (Proposed_patch.make ~id:patch_id ~target ~expected_identity:before
         ~resulting_identity:after
         ~edits:[ Text_edit.make ~range:edit_range ~replacement:"Heading" ]
         ~reason:"Synchronize the explicit sidecar annotation" ~provenance)
  in
  let artifact_id = get (Identifier.make "artifact:readme") in
  let diagnostic =
    get
      (Diagnostic.make ~code:Diagnostic.Divergent
         ~effective_severity:Diagnostic.Warning
         ~message:"Inline and sidecar annotations differ"
         ~location:
           {
             Diagnostic.artifact = Some artifact_id;
             region = None;
             annotation = None;
             range = Some edit_range;
           }
         ~suggested_fixes:[ patch ] ())
  in
  let metrics_path =
    get
      (Workspace_path.of_segments
         [ "fixtures"; "basic"; "runs"; "metrics.jsonl" ])
  in
  let row_filter =
    get (Selector.row_filter ~where:[ ("metric", "latency") ])
  in
  let metrics_content =
    {|{"run":"a","metric":"latency","value":42,"unit":"ms"}
{"run":"a","metric":"throughput","value":1200,"unit":"rps"}
|}
  in
  let snapshot =
    get
      (Resolution_snapshot.make
         ~target:
           {
             Reference.artifact = Artifact.Workspace metrics_path;
             selector = Some (Selector.Row_filter row_filter);
             interpreter = Some "jsonl";
           }
         ~artifact_identity:(Content_identity.of_content metrics_content)
         ~region_fingerprint:"sha256:region" ~display:"latency row"
         ~observed_at:"2026-06-11T00:00:00Z" ())
  in
  let conflict =
    Conflict.Identity_mismatch
      {
        patch_id;
        target;
        expected = before;
        actual = Content_identity.of_content "Changed\n";
      }
  in
  let result =
    get
      (Command_result.make ~command:"apply"
         ~termination:Command_result.Completed
         ~effect:Command_result.Conflicted ~diagnostics:[ diagnostic ]
         ~patches:[ patch ]
         ~changed_artifacts:
           [ { Command_result.path = target; before; after } ]
         ~conflicts:[ conflict ] ~snapshots:[ snapshot ]
         ~summary:
           [
             ("applied", Command_result.Count 1);
             ("dryRun", Command_result.Flag false);
             ("mode", Command_result.Text "strict");
           ]
         ())
  in
  result |> Normal.Command_result.normalize |> Normal_json.command_result
  |> Yojson.Safe.pretty_to_channel stdout;
  print_newline ()
