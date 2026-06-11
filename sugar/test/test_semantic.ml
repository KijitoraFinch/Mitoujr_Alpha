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
    ~edits ~reason:"test update" ~provenance

let test_patch () =
  check_error (sample_patch []);
  let range = expect_ok (Text_range.make ~start:0 ~end_:0) in
  ignore
    (expect_ok
       (sample_patch [ Text_edit.make ~range ~replacement:"inserted" ]))

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
    (Diagnostic.effective_severity diagnostic |> Diagnostic.severity_string)

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
      ( make_result ~effect:Command_result.Patches_proposed (),
        "patches-proposed",
        "success" );
      (make_result ~effect:Command_result.Applied (), "applied", "success");
      ( make_result ~effect:Command_result.Conflicted (),
        "conflict",
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
  check_error
    (Command_result.make ~command:"" ~termination:Command_result.Completed
       ~effect:Command_result.No_change ())

let () =
  Alcotest.run "monika_sugar semantic model"
    [
      ( "construction",
        [
          Alcotest.test_case "identifier" `Quick test_identifier;
          Alcotest.test_case "range" `Quick test_range;
          Alcotest.test_case "patch" `Quick test_patch;
          Alcotest.test_case "diagnostic severity" `Quick
            test_diagnostic_severity;
          Alcotest.test_case "command result" `Quick test_command_result;
        ] );
      ( "workspace path",
        [
          Alcotest.test_case "POSIX" `Quick test_posix_paths;
          Alcotest.test_case "Windows" `Quick test_windows_paths;
          QCheck_alcotest.to_alcotest path_round_trip;
        ] );
      ( "content identity",
        [ Alcotest.test_case "SHA-256" `Quick test_content_identity ] );
    ]
