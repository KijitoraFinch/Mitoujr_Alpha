open Monika_sugar

let expect_ok = function
  | Ok value -> value
  | Error message -> Alcotest.fail message

let check_error = function
  | Ok _ -> Alcotest.fail "expected construction to fail"
  | Error _ -> ()

let test_identifier () =
  check_error (Identifier.make "");
  let value = expect_ok (Identifier.make "artifact:readme") in
  Alcotest.(check string) "preserves value" "artifact:readme"
    (Identifier.to_string value)

let test_range () =
  check_error (Text_range.make ~start:(-1) ~end_:0);
  check_error (Text_range.make ~start:2 ~end_:1);
  let range = expect_ok (Text_range.make ~start:2 ~end_:5) in
  Alcotest.(check int) "start" 2 (Text_range.start range);
  Alcotest.(check int) "end" 5 (Text_range.end_ range);
  Alcotest.(check int) "length" 3 (Text_range.length range)

let test_posix_paths () =
  let path =
    expect_ok
      (Workspace_path.of_native_string ~flavor:Workspace_path.Posix
         "docs/./guide/../README.md")
  in
  Alcotest.(check string) "normalized" "docs/README.md"
    (Workspace_path.to_canonical_string path);
  let backslash =
    expect_ok
      (Workspace_path.of_native_string ~flavor:Workspace_path.Posix
         "docs\\name")
  in
  Alcotest.(check string) "backslash is data on POSIX" "docs%5Cname"
    (Workspace_path.to_canonical_string backslash);
  List.iter
    (fun input ->
      check_error
        (Workspace_path.of_native_string ~flavor:Workspace_path.Posix input))
    [ ""; "/etc/passwd"; "../outside"; "a/../../outside"; "a\000b" ]
  ;
  List.iter
    (fun input -> check_error (Workspace_path.of_canonical_string input))
    [ "has space"; "lower%ff"; "%41.txt"; "a//b" ]

let test_windows_paths () =
  let path =
    expect_ok
      (Workspace_path.of_native_string ~flavor:Workspace_path.Windows
         "docs\\guide/../README.md")
  in
  Alcotest.(check string) "normalizes separators" "docs/README.md"
    (Workspace_path.to_canonical_string path);
  List.iter
    (fun input ->
      check_error
        (Workspace_path.of_native_string ~flavor:Workspace_path.Windows input))
    [ "C:\\work\\file"; "c:file"; "\\\\server\\share"; "\\rooted"; "/rooted" ]

let valid_segment value =
  String.length value > 0
  && not (String.contains value '\000')
  && not (String.contains value '/')
  && not (String.equal value ".")
  && not (String.equal value "..")

let path_round_trip =
  let open QCheck in
  Test.make ~name:"canonical paths preserve arbitrary filename bytes"
    ~count:1000
    (list_of_size (Gen.int_range 1 5) (string_of_size (Gen.int_range 1 20)))
    (fun segments ->
      assume (List.for_all valid_segment segments);
      let path = Result.get_ok (Workspace_path.of_segments segments) in
      let encoded = Workspace_path.to_canonical_string path in
      match Workspace_path.of_canonical_string encoded with
      | Error _ -> false
      | Ok decoded -> Workspace_path.equal path decoded)

let test_content_identity () =
  let digest = Content_digest.of_content "" in
  Alcotest.(check string)
    "known content digest"
    "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    (Content_digest.to_string digest);
  let empty = Content_identity.of_content "" in
  Alcotest.(check string)
    "known SHA-256"
    "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    (Content_identity.display_hash empty);
  Alcotest.(check int) "byte length" 0 (Content_identity.byte_length empty);
  Alcotest.(check bool) "deterministic" true
    (Content_identity.equal (Content_identity.of_content "abc")
       (Content_identity.of_content "abc"));
  check_error (Content_identity.make ~sha256:"ABC" ~byte_length:0);
  check_error
    (Content_identity.make ~sha256:(String.make 64 'a') ~byte_length:(-1))

let sample_patch edits =
  let id = expect_ok (Identifier.make "patch:one") in
  let target = expect_ok (Workspace_path.of_segments [ "file.txt" ]) in
  let provenance = expect_ok (Provenance.make ~source:"test" ()) in
  Proposed_patch.make ~id ~target
    ~expected_identity:(Content_identity.of_content "old")
    ~resulting_identity:(Content_identity.of_content "new")
    ~edits ~reason:"test update" ~provenance

let test_patch () =
  check_error (sample_patch []);
  let range = expect_ok (Text_range.make ~start:0 ~end_:0) in
  ignore
    (expect_ok
       (sample_patch [ Text_edit.make ~range ~replacement:"inserted" ]))

let test_artifact_origin_and_reference_target () =
  let path =
    expect_ok
      (Workspace_path.of_native_string ~flavor:Workspace_path.Posix
         "runs/metrics.jsonl")
  in
  let workspace = Artifact.workspace path in
  ignore workspace;
  check_error (Artifact.git ~repo:"" ~path:"file.txt" ());
  check_error (Artifact.git ~repo:"repo" ~rev:"" ~path:"file.txt" ());
  check_error (Artifact.git ~repo:"repo" ~path:"" ());
  check_error (Artifact.web "");
  check_error (Artifact.generated "");
  check_error (Artifact.external_ "");
  let git = expect_ok (Artifact.git ~repo:"repo" ~path:"file.txt" ()) in
  (match git with
  | Artifact.Git value ->
      Alcotest.(check string) "repo" "repo" value.repo
  | _ -> Alcotest.fail "expected git origin");
  check_error (Reference.make_target ~artifact:workspace ~interpreter:"" ());
  let target =
    expect_ok
      (Reference.make_target ~artifact:workspace ~interpreter:"jsonl" ())
  in
  Alcotest.(check (option string)) "interpreter" (Some "jsonl")
    target.interpreter

let test_selector_and_expectation () =
  check_error (Selector.Field_name.make "");
  let metric = expect_ok (Selector.Field_name.make "metric") in
  let phase = expect_ok (Selector.Field_name.make "phase") in
  check_error (Selector.Row_filter.make []);
  check_error
    (Selector.Row_filter.make
       [
         (metric, Selector.Literal.String "latency");
         (metric, Selector.Literal.String "throughput");
       ]);
  let filter =
    expect_ok
      (Selector.Row_filter.make
         [
           (phase, Selector.Literal.String "warmup");
           (metric, Selector.Literal.String "latency");
         ])
  in
  let conditions =
    Selector.Row_filter.conditions filter
    |> List.map (fun (field, value) ->
           (Selector.Field_name.to_string field, value))
  in
  Alcotest.(check int) "row-filter remains non-empty" 2
    (List.length conditions);
  Alcotest.(check string)
    "row-filter conditions are canonical"
    "metric"
    (conditions |> List.hd |> fst);
  check_error (Content_digest.of_hex "");
  check_error (Content_digest.of_hex (String.make 64 'A'));
  let digest =
    expect_ok
      (Content_digest.of_hex
         "aafdf097b034d51e1794cb111ce16c46f88e9ef17da6f859a00fd39288e69ef6")
  in
  let expectation = Expectation.Digest digest in
  (match expectation with
  | Expectation.Digest digest ->
      Alcotest.(check string)
        "digest value"
        "sha256:aafdf097b034d51e1794cb111ce16c46f88e9ef17da6f859a00fd39288e69ef6"
        (Content_digest.to_string digest));
  let id = expect_ok (Identifier.make "latency-run-a") in
  let artifact_path =
    expect_ok
      (Workspace_path.of_native_string ~flavor:Workspace_path.Posix
         "runs/metrics.jsonl")
  in
  let target =
    expect_ok
      (Reference.make_target ~artifact:(Artifact.workspace artifact_path)
         ~selector:(Selector.Row_filter filter) ~interpreter:"jsonl" ())
  in
  let reference =
    Reference.make ~id ~target ~binding:Reference.Pinned
      ~expectations:[ expectation ] ()
  in
  Alcotest.(check int) "typed expectation is retained" 1
    (List.length (Reference.expectations reference))

let test_diagnostic_severity () =
  Alcotest.(check string) "registry default" "error"
    (Diagnostic.default_severity Diagnostic.Unresolved_ref
    |> Diagnostic.severity_string);
  let diagnostic =
    expect_ok
      (Diagnostic.make ~code:Diagnostic.Unresolved_ref
         ~effective_severity:Diagnostic.Warning ~message:"not resolved" ())
  in
  Alcotest.(check string) "policy override" "warning"
    (Diagnostic.effective_severity diagnostic |> Diagnostic.severity_string);
  check_error
    (Diagnostic.make ~code:Diagnostic.Duplicate ~message:"empty location"
       ~location:
         {
           Diagnostic.artifact = None;
           region = None;
           annotation = None;
           range = None;
         }
       ())

let make_result ?(termination = Command_result.Completed)
    ?(effect = Command_result.No_change) ?(diagnostics = []) () =
  expect_ok
    (Command_result.make ~command:"check" ~termination ~effect ~diagnostics ())

let test_command_result () =
  let error =
    expect_ok
      (Diagnostic.make ~code:Diagnostic.Divergent ~message:"mismatch" ())
  in
  let warning =
    expect_ok
      (Diagnostic.make ~code:Diagnostic.Duplicate ~message:"duplicate" ())
  in
  let cases =
    [
      (make_result (), "ok", "success");
      ( make_result ~diagnostics:[ warning ] (),
        "diagnostics-found",
        "success" );
      ( make_result ~diagnostics:[ error ] (),
        "diagnostics-found",
        "diagnostic-error" );
      ( make_result
          ~termination:(Command_result.Usage_failure "bad input")
          (),
        "invalid-input",
        "usage-error" );
      ( make_result
          ~termination:(Command_result.Internal_failure "bug")
          (),
        "internal-error",
        "internal-error" );
    ]
  in
  List.iter
    (fun (result, status, exit_class) ->
      Alcotest.(check string) "status" status
        (Command_result.status result |> Command_result.status_string);
      Alcotest.(check string) "exit class" exit_class
        (Command_result.exit_class result |> Command_result.exit_class_string))
    cases;
  let patch_range = expect_ok (Text_range.make ~start:0 ~end_:0) in
  let patch =
    sample_patch [ Text_edit.make ~range:patch_range ~replacement:"new" ]
    |> expect_ok
  in
  let changed_path =
    expect_ok
      (Workspace_path.of_native_string ~flavor:Workspace_path.Posix
         "changed.txt")
  in
  let before = Content_identity.of_content "old" in
  let after = Content_identity.of_content "new" in
  let patch_result =
    expect_ok
      (Command_result.make ~command:"derive"
         ~termination:Command_result.Completed
         ~effect:Command_result.Patches_proposed ~patches:[ patch ] ())
  in
  Alcotest.(check string) "patch status" "patches-proposed"
    (Command_result.status patch_result |> Command_result.status_string);
  let applied_result =
    expect_ok
      (Command_result.make ~command:"apply"
         ~termination:Command_result.Completed ~effect:Command_result.Applied
         ~changed_artifacts:
           [ { Command_result.path = changed_path; before; after } ]
         ())
  in
  Alcotest.(check string) "applied status" "applied"
    (Command_result.status applied_result |> Command_result.status_string);
  let patch_id = Proposed_patch.id patch in
  let conflict =
    Conflict.Identity_mismatch
      { patch_id; target = changed_path; expected = before; actual = after }
  in
  let conflict_result =
    expect_ok
      (Command_result.make ~command:"apply"
         ~termination:Command_result.Completed
         ~effect:Command_result.Conflicted ~conflicts:[ conflict ] ())
  in
  Alcotest.(check string) "conflict status" "conflict"
    (Command_result.status conflict_result |> Command_result.status_string);
  check_error
    (Command_result.make ~command:"" ~termination:Command_result.Completed
       ~effect:Command_result.No_change ());
  check_error
    (Command_result.make ~command:"check"
       ~termination:Command_result.Completed ~effect:Command_result.No_change
       ~summary:
         [
           ("count", Command_result.Count 1);
           ("count", Command_result.Count 2);
       ]
       ());
  check_error
    (Command_result.make ~command:"derive"
       ~termination:Command_result.Completed
       ~effect:Command_result.Patches_proposed ());
  check_error
    (Command_result.make ~command:"apply"
       ~termination:Command_result.Completed ~effect:Command_result.Applied ());
  check_error
    (Command_result.make ~command:"apply"
       ~termination:Command_result.Completed ~effect:Command_result.Conflicted ());
  check_error
    (Command_result.make ~command:"check"
       ~termination:Command_result.Completed ~effect:Command_result.No_change
       ~conflicts:[ conflict ] ());
  check_error
    (Command_result.make ~command:"check"
       ~termination:Command_result.Completed ~effect:Command_result.No_change
       ~changed_artifacts:
         [ { Command_result.path = changed_path; before; after } ]
       ());
  check_error
    (Command_result.make ~command:"apply"
       ~termination:Command_result.Completed ~effect:Command_result.Applied
       ~changed_artifacts:
         [ { Command_result.path = changed_path; before; after } ]
       ~conflicts:[ conflict ] ());
  check_error
    (Command_result.make ~command:"apply"
       ~termination:Command_result.Completed ~effect:Command_result.Conflicted
       ~conflicts:[ conflict ]
       ~changed_artifacts:
         [ { Command_result.path = changed_path; before; after } ]
       ());
  check_error
    (Command_result.make ~command:"derive"
       ~termination:Command_result.Completed
       ~effect:Command_result.Patches_proposed ~patches:[ patch ]
       ~changed_artifacts:
         [ { Command_result.path = changed_path; before; after } ]
       ());
  check_error
    (Command_result.make ~command:"apply"
       ~termination:(Command_result.Usage_failure "bad")
       ~effect:Command_result.Applied
       ~changed_artifacts:
         [ { Command_result.path = changed_path; before; after } ]
       ())

let json_of_result result =
  result |> Normal.Command_result.normalize |> Normal_json.command_result

let assoc_has name = function
  | `Assoc fields -> List.mem_assoc name fields
  | _ -> false

let rec contains_null = function
  | `Null -> true
  | `Assoc fields -> List.exists (fun (_, value) -> contains_null value) fields
  | `List values -> List.exists contains_null values
  | `Bool _ | `Int _ | `Intlit _ | `Float _ | `String _ | `Tuple _
  | `Variant _ ->
      false

let test_normal_command_result () =
  let artifact_a = expect_ok (Identifier.make "artifact:a") in
  let artifact_b = expect_ok (Identifier.make "artifact:b") in
  let diagnostic artifact code message =
    expect_ok
      (Diagnostic.make ~code ~message
         ~location:
           {
             Diagnostic.artifact = Some artifact;
             region = None;
             annotation = None;
             range = None;
           }
         ())
  in
  let first =
    diagnostic artifact_b Diagnostic.Unresolved_ref "second artifact"
  in
  let second = diagnostic artifact_a Diagnostic.Duplicate "first artifact" in
  let make diagnostics =
    expect_ok
      (Command_result.make ~command:"check"
         ~termination:Command_result.Completed ~effect:Command_result.No_change
         ~diagnostics ())
  in
  let forward = json_of_result (make [ first; second ]) in
  let reverse = json_of_result (make [ second; first ]) in
  Alcotest.(check string) "normalization ignores input order"
    (Yojson.Safe.to_string forward)
    (Yojson.Safe.to_string reverse);
  List.iter
    (fun field ->
      Alcotest.(check bool) (field ^ " is always present") true
        (assoc_has field forward))
    [ "diagnostics"; "patches"; "changedArtifacts"; "conflicts"; "snapshots" ];
  Alcotest.(check bool) "summary is omitted" false (assoc_has "summary" forward);
  Alcotest.(check bool) "null is never emitted" false (contains_null forward);
  let empty_summary =
    expect_ok
      (Command_result.make ~command:"check"
         ~termination:Command_result.Completed ~effect:Command_result.No_change
         ~summary:[] ())
    |> json_of_result
  in
  Alcotest.(check bool) "empty summary is present" true
    (assoc_has "summary" empty_summary)

let path value =
  expect_ok (Workspace_path.of_native_string ~flavor:Workspace_path.Posix value)

let edit start end_ replacement =
  let range = expect_ok (Text_range.make ~start ~end_) in
  Text_edit.make ~range ~replacement

let workspace_patch ?(id = "patch:test") ~target ~original ~result edits =
  let id = expect_ok (Identifier.make id) in
  let provenance = expect_ok (Provenance.make ~source:"test" ()) in
  expect_ok
    (Proposed_patch.make ~id ~target
       ~expected_identity:(Content_identity.of_content original)
       ~resulting_identity:(Content_identity.of_content result)
       ~edits ~reason:"workspace operation test" ~provenance)

let assoc_fields = function
  | `Assoc fields -> fields
  | _ -> Alcotest.fail "expected JSON object"

let replace_field name value json =
  `Assoc
    (assoc_fields json
    |> List.map (fun (field, existing) ->
           if String.equal field name then (field, value)
           else (field, existing)))

let remove_field name json =
  `Assoc
    (assoc_fields json
    |> List.filter (fun (field, _) -> not (String.equal field name)))

let add_field name value json = `Assoc ((name, value) :: assoc_fields json)

let expect_decode_error name json =
  match Normal_decode.proposed_patch json with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail (name ^ " decoded successfully")

let test_proposed_patch_decoder () =
  let target = path "decode.txt" in
  let patch =
    workspace_patch ~target ~original:"old" ~result:"new"
      [ edit 0 3 "new" ]
  in
  let json = patch |> Normal.Patch.normalize |> Normal_json.patch in
  let decoded = expect_ok (Normal_decode.proposed_patch json) in
  Alcotest.(check string) "round-trip patch normal form"
    (json |> Yojson.Safe.to_string)
    (decoded |> Normal.Patch.normalize |> Normal_json.patch
    |> Yojson.Safe.to_string);
  List.iter
    (fun (name, invalid_json) -> expect_decode_error name invalid_json)
    [
      ("unknown field", add_field "unexpected" (`Bool true) json);
      ("missing reason", remove_field "reason" json);
      ("null target", replace_field "target" `Null json);
      ("bad target", replace_field "target" (`String "../x") json);
      ("empty edits", replace_field "edits" (`List []) json);
      ("empty reason", replace_field "reason" (`String "") json);
      ( "bad identity",
        replace_field "expectedContentIdentity"
          (`Assoc
            [
              ("hash", `String ("sha256:" ^ String.make 64 'A'));
              ("size", `Int 3);
            ])
          json );
    ]

let apply_content snapshot patch =
  match Workspace_ops.apply_patch snapshot patch with
  | Workspace_ops.Applied applied ->
      let target = Proposed_patch.target patch in
      let file = Option.get (Workspace_snapshot.find target applied.snapshot) in
      (applied.snapshot, Workspace_snapshot.file_content file)
  | Workspace_ops.No_change _ -> Alcotest.fail "expected patch application"
  | Workspace_ops.Conflict _ -> Alcotest.fail "unexpected patch conflict"

let test_workspace_snapshot () =
  let a = path "a.txt" in
  let b = path "nested/b.txt" in
  let left = expect_ok (Workspace_snapshot.make [ (b, "B"); (a, "A") ]) in
  let right = expect_ok (Workspace_snapshot.make [ (a, "A"); (b, "B") ]) in
  Alcotest.(check bool) "input order is irrelevant" true
    (Workspace_snapshot.equal left right);
  Alcotest.(check (list string))
    "files are canonical-path sorted"
    [ "a.txt"; "nested/b.txt" ]
    (Workspace_snapshot.files left
    |> List.map (fun file ->
           Workspace_snapshot.file_path file
           |> Workspace_path.to_canonical_string));
  check_error (Workspace_snapshot.make [ (a, "A"); (a, "duplicate") ])

let test_text_edit_application () =
  let target = path "data.bin" in
  let cases =
    [
      ("abcdef", "abc-def", [ edit 3 3 "-" ]);
      ("abcdef", "adef", [ edit 1 3 "" ]);
      ("abcdef", "abXYef", [ edit 2 4 "XY" ]);
      ("abcdef", "aXdef", [ edit 3 3 "X"; edit 1 3 "" ]);
      ("abcdef", "AbcdEF", [ edit 4 6 "EF"; edit 0 1 "A" ]);
      ("\000\255a", "\000Ba", [ edit 1 2 "B" ]);
      ("", "new", [ edit 0 0 "new" ]);
    ]
  in
  List.iter
    (fun (original, result, edits) ->
      let snapshot =
        expect_ok (Workspace_snapshot.make [ (target, original) ])
      in
      let patch = workspace_patch ~target ~original ~result edits in
      let _, actual = apply_content snapshot patch in
      Alcotest.(check string) "applied content" result actual)
    cases

let test_workspace_conflicts () =
  let target = path "file.txt" in
  let snapshot = expect_ok (Workspace_snapshot.make [ (target, "abcdef") ]) in
  let expect_conflict patch predicate =
    match Workspace_ops.apply_patch snapshot patch with
    | Workspace_ops.Conflict conflict ->
        Alcotest.(check bool) "conflict kind" true (predicate conflict)
    | Workspace_ops.Applied _ | Workspace_ops.No_change _ ->
        Alcotest.fail "expected conflict"
  in
  workspace_patch ~target ~original:"other" ~result:"Other"
    [ edit 0 1 "O" ]
  |> fun patch ->
  expect_conflict patch (function Conflict.Identity_mismatch _ -> true | _ -> false);
  workspace_patch ~target ~original:"abcdef" ~result:"abcdefX"
    [ edit 6 7 "X" ]
  |> fun patch ->
  expect_conflict patch (function
    | Conflict.Range_out_of_bounds _ -> true
    | _ -> false);
  workspace_patch ~target ~original:"abcdef" ~result:"aXYef"
    [ edit 1 3 "X"; edit 2 4 "Y" ]
  |> fun patch ->
  expect_conflict patch (function Conflict.Overlapping_edits _ -> true | _ -> false);
  workspace_patch ~target ~original:"abcdef" ~result:"declared"
    [ edit 0 1 "A" ]
  |> fun patch ->
  expect_conflict patch (function
    | Conflict.Result_identity_mismatch _ -> true
    | _ -> false);
  let missing = path "missing.txt" in
  let patch =
    workspace_patch ~target:missing ~original:"" ~result:"x" [ edit 0 0 "x" ]
  in
  expect_conflict patch (function Conflict.Missing_artifact _ -> true | _ -> false)

let test_patch_reapplication () =
  let target = path "file.txt" in
  let snapshot = expect_ok (Workspace_snapshot.make [ (target, "abc") ]) in
  let patch =
    workspace_patch ~target ~original:"abc" ~result:"aXYZc"
      [ edit 1 2 "XYZ" ]
  in
  let applied, content = apply_content snapshot patch in
  Alcotest.(check string) "first application" "aXYZc" content;
  match Workspace_ops.apply_patch applied patch with
  | Workspace_ops.No_change unchanged ->
      Alcotest.(check bool) "snapshot is unchanged" true
        (Workspace_snapshot.equal applied unchanged)
  | Workspace_ops.Applied _ | Workspace_ops.Conflict _ ->
      Alcotest.fail "reapplication must be a no-op"

let write_file file content =
  let output = open_out_bin file in
  Fun.protect
    ~finally:(fun () -> close_out_noerr output)
    (fun () -> output_string output content)

let read_file file =
  let input = open_in_bin file in
  Fun.protect
    ~finally:(fun () -> close_in_noerr input)
    (fun () -> really_input_string input (in_channel_length input))

let rec remove_tree path =
  if Sys.file_exists path || Sys.file_exists (Filename.dirname path) then
    match Unix.lstat path with
    | { Unix.st_kind = Unix.S_DIR; _ } ->
        Sys.readdir path
        |> Array.iter (fun entry -> remove_tree (Filename.concat path entry));
        Unix.rmdir path
    | _ -> Sys.remove path
    | exception (Unix.Unix_error _ | Sys_error _) -> ()

let with_temp_workspace f =
  let root = Filename.temp_dir "monika-sugar-" "-workspace" in
  Fun.protect ~finally:(fun () -> remove_tree root) (fun () -> f root)

let result_status result =
  Command_result.status result |> Command_result.status_string

let result_exit_class result =
  Command_result.exit_class result |> Command_result.exit_class_string

let check_filesystem_apply_result ~status ~exit_class result =
  Alcotest.(check string) "status" status (result_status result);
  Alcotest.(check string) "exitClass" exit_class (result_exit_class result)

let test_filesystem_apply_write_and_dry_run () =
  with_temp_workspace (fun root ->
      let file = Filename.concat root "file.txt" in
      write_file file "abc";
      let target = path "file.txt" in
      let patch =
        workspace_patch ~target ~original:"abc" ~result:"aXYZc"
          [ edit 1 2 "XYZ" ]
      in
      let dry_run =
        Filesystem_apply.apply ~workspace:root ~patch ~dry_run:true
      in
      check_filesystem_apply_result ~status:"patches-proposed"
        ~exit_class:"success" dry_run;
      Alcotest.(check string) "dry-run does not write" "abc" (read_file file);
      let applied =
        Filesystem_apply.apply ~workspace:root ~patch ~dry_run:false
      in
      check_filesystem_apply_result ~status:"applied" ~exit_class:"success"
        applied;
      Alcotest.(check string) "write applies replacement" "aXYZc"
        (read_file file);
      let repeated =
        Filesystem_apply.apply ~workspace:root ~patch ~dry_run:false
      in
      check_filesystem_apply_result ~status:"ok" ~exit_class:"success"
        repeated;
      Alcotest.(check string) "repeated apply is stable" "aXYZc"
        (read_file file))

let test_filesystem_apply_conflicts_do_not_write () =
  let check_case name patch =
    with_temp_workspace (fun root ->
        let file = Filename.concat root "file.txt" in
        write_file file "abcdef";
        let result =
          Filesystem_apply.apply ~workspace:root ~patch ~dry_run:false
        in
        check_filesystem_apply_result ~status:"conflict"
          ~exit_class:"diagnostic-error" result;
        Alcotest.(check string) name "abcdef" (read_file file))
  in
  let target = path "file.txt" in
  check_case "identity mismatch does not write"
    (workspace_patch ~target ~original:"other" ~result:"Other"
       [ edit 0 1 "O" ]);
  check_case "range conflict does not write"
    (workspace_patch ~target ~original:"abcdef" ~result:"abcdefX"
       [ edit 6 7 "X" ]);
  check_case "overlap conflict does not write"
    (workspace_patch ~target ~original:"abcdef" ~result:"aXYef"
       [ edit 1 3 "X"; edit 2 4 "Y" ]);
  check_case "result identity conflict does not write"
    (workspace_patch ~target ~original:"abcdef" ~result:"declared"
       [ edit 0 1 "A" ])

let test_filesystem_apply_preserves_posix_mode () =
  if not Sys.win32 then
    with_temp_workspace (fun root ->
        let file = Filename.concat root "file.txt" in
        write_file file "abc";
        Unix.chmod file 0o4755;
        let target = path "file.txt" in
        let patch =
          workspace_patch ~target ~original:"abc" ~result:"ABC"
            [ edit 0 3 "ABC" ]
        in
        let result =
          Filesystem_apply.apply ~workspace:root ~patch ~dry_run:false
        in
        check_filesystem_apply_result ~status:"applied" ~exit_class:"success"
          result;
        let mode = (Unix.stat file).Unix.st_perm land 0o7777 in
        Alcotest.(check int) "preserves mode including special bits" 0o4755 mode)

let filesystem_safety_reason result =
  match Command_result.conflicts result with
  | [ Conflict.Filesystem_safety { reason; _ } ] ->
      Some (Conflict.filesystem_safety_reason_string reason)
  | _ -> None

let test_filesystem_apply_safety () =
  with_temp_workspace (fun root ->
      let target = path "dir" in
      Unix.mkdir (Filename.concat root "dir") 0o700;
      let patch =
        workspace_patch ~target ~original:"" ~result:"x" [ edit 0 0 "x" ]
      in
      let result =
        Filesystem_apply.apply ~workspace:root ~patch ~dry_run:false
      in
      check_filesystem_apply_result ~status:"conflict"
        ~exit_class:"diagnostic-error" result;
      Alcotest.(check (option string)) "directory target safety reason"
        (Some "target-not-regular-file")
        (filesystem_safety_reason result));
  if not Sys.win32 then
    with_temp_workspace (fun root ->
        let real = Filename.concat root "real.txt" in
        let link = Filename.concat root "link.txt" in
        write_file real "abc";
        Unix.symlink "real.txt" link;
        let target = path "link.txt" in
        let patch =
          workspace_patch ~target ~original:"abc" ~result:"ABC"
            [ edit 0 3 "ABC" ]
        in
        let result =
          Filesystem_apply.apply ~workspace:root ~patch ~dry_run:false
        in
        check_filesystem_apply_result ~status:"conflict"
          ~exit_class:"diagnostic-error" result;
        Alcotest.(check (option string)) "symlink target safety reason"
          (Some "target-is-symlink")
          (filesystem_safety_reason result);
        Alcotest.(check string) "symlink target does not rewrite referent" "abc"
          (read_file real));
    with_temp_workspace (fun root ->
        let real_dir = Filename.concat root "real-dir" in
        let link_dir = Filename.concat root "link-dir" in
        Unix.mkdir real_dir 0o700;
        let real = Filename.concat real_dir "file.txt" in
        write_file real "abc";
        Unix.symlink "real-dir" link_dir;
        let target = path "link-dir/file.txt" in
        let patch =
          workspace_patch ~target ~original:"abc" ~result:"ABC"
            [ edit 0 3 "ABC" ]
        in
        let result =
          Filesystem_apply.apply ~workspace:root ~patch ~dry_run:false
        in
        check_filesystem_apply_result ~status:"conflict"
          ~exit_class:"diagnostic-error" result;
        Alcotest.(check (option string)) "symlink parent safety reason"
          (Some "symlink-component")
          (filesystem_safety_reason result);
        Alcotest.(check string) "symlink parent does not rewrite referent" "abc"
          (read_file real));
    with_temp_workspace (fun root ->
        let file = Filename.concat root "file.txt" in
        write_file file "abc";
        let target = path "file.txt" in
        let patch =
          workspace_patch ~target ~original:"abc" ~result:"ABC"
            [ edit 0 3 "ABC" ]
        in
        Fun.protect
          ~finally:(fun () -> Unix.chmod root 0o700)
          (fun () ->
            Unix.chmod root 0o500;
            let result =
              Filesystem_apply.apply ~workspace:root ~patch ~dry_run:false
            in
            check_filesystem_apply_result ~status:"internal-error"
              ~exit_class:"internal-error" result;
            Alcotest.(check string)
              "temporary file failure preserves target"
              "abc" (read_file file)))

let () =
  Alcotest.run "monika_sugar semantic model"
    [
      ( "construction",
        [
          Alcotest.test_case "identifier" `Quick test_identifier;
          Alcotest.test_case "range" `Quick test_range;
          Alcotest.test_case "patch" `Quick test_patch;
          Alcotest.test_case "artifact origin and reference target" `Quick
            test_artifact_origin_and_reference_target;
          Alcotest.test_case "selector and expectation" `Quick
            test_selector_and_expectation;
          Alcotest.test_case "diagnostic severity" `Quick
            test_diagnostic_severity;
          Alcotest.test_case "command result" `Quick test_command_result;
          Alcotest.test_case "normal command result" `Quick
            test_normal_command_result;
          Alcotest.test_case "proposed patch decoder" `Quick
            test_proposed_patch_decoder;
        ] );
      ( "workspace path",
        [
          Alcotest.test_case "POSIX" `Quick test_posix_paths;
          Alcotest.test_case "Windows" `Quick test_windows_paths;
          QCheck_alcotest.to_alcotest path_round_trip;
        ] );
      ( "content identity",
        [ Alcotest.test_case "SHA-256" `Quick test_content_identity ] );
      ( "workspace operations",
        [
          Alcotest.test_case "snapshot normalization" `Quick
            test_workspace_snapshot;
          Alcotest.test_case "text edits" `Quick test_text_edit_application;
          Alcotest.test_case "conflicts" `Quick test_workspace_conflicts;
          Alcotest.test_case "patch reapplication" `Quick
            test_patch_reapplication;
        ] );
      ( "filesystem apply",
        [
          Alcotest.test_case "write and dry-run" `Quick
            test_filesystem_apply_write_and_dry_run;
          Alcotest.test_case "conflicts do not write" `Quick
            test_filesystem_apply_conflicts_do_not_write;
          Alcotest.test_case "preserves POSIX mode" `Quick
            test_filesystem_apply_preserves_posix_mode;
          Alcotest.test_case "safety" `Quick test_filesystem_apply_safety;
        ] );
    ]
