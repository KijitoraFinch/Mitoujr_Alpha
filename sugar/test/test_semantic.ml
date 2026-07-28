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

let test_scoped_identifiers_and_region_address () =
  let left_artifact = expect_ok (Artifact_id.make "artifact:left") in
  let right_artifact = expect_ok (Artifact_id.make "artifact:right") in
  let left =
    expect_ok (Region_id.make ~artifact:left_artifact ~local:"heading")
  in
  let same =
    expect_ok (Region_id.make ~artifact:left_artifact ~local:"heading")
  in
  let other_scope =
    expect_ok (Region_id.make ~artifact:right_artifact ~local:"heading")
  in
  Alcotest.(check bool) "same scoped ID" true (Region_id.equal left same);
  Alcotest.(check bool) "artifact participates in identity" false
    (Region_id.equal left other_scope);
  check_error (Reference_id.make ~artifact:left_artifact ~local:"");
  let target_path = expect_ok (Workspace_path.of_segments [ "docs"; "note.md" ]) in
  let address =
    expect_ok
      (Region_address.make ~artifact:(Artifact.workspace target_path)
         ~selector:Selector.Whole_artifact ~interpreter:"markdown" ())
  in
  Alcotest.(check string) "unresolved address retains artifact" "docs/note.md"
    (match Region_address.artifact address with
    | Artifact.Workspace path -> Workspace_path.to_canonical_string path
    | _ -> Alcotest.fail "expected workspace address");
  let annotation =
    expect_ok (Annotation_id.make ~artifact:right_artifact ~local:"annotation")
  in
  check_error
    (Diagnostic.make ~code:Diagnostic.Divergent ~message:"scope mismatch"
       ~location:
         {
           Diagnostic.artifact = Some left_artifact;
           region = None;
           annotation = Some annotation;
           range = None;
         }
       ());
  let artifact =
    expect_ok
      (Artifact.make ~id:left_artifact
         ~origin:(Artifact.workspace target_path)
         ~content_identity:(Content_identity.of_content "") ())
  in
  let region =
    expect_ok
      (Region.make ~id:left ~selector:Selector.Whole_artifact
         ~interpreter:"plain-text" ())
  in
  check_error
    (Command_result.make ~command:"inspect"
       ~termination:Command_result.Completed ~effect:Command_result.No_change
       ~artifacts:[ artifact ] ~regions:[ region; region ] ());
  check_error
    (Command_result.make ~command:"inspect"
       ~termination:Command_result.Completed ~effect:Command_result.No_change
       ~regions:[ region ] ())

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
    (list_size (Gen.int_range 1 5) (string_size (Gen.int_range 1 20)))
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
  let buffer = Bytes.of_string "prefix-body-suffix" in
  let incremental =
    Content_digest.Incremental.empty ()
    |> fun state ->
    Content_digest.Incremental.feed_bytes state buffer ~offset:0 ~length:6
    |> fun state ->
    Content_digest.Incremental.feed_bytes state buffer ~offset:7 ~length:4
    |> Content_digest.Incremental.finish
  in
  Alcotest.(check bool) "incremental digest"
    true
    (Content_digest.equal incremental (Content_digest.of_content "prefixbody"));
  let incremental_identity =
    expect_ok
      (Content_identity.of_digest ~digest:incremental ~byte_length:10)
  in
  Alcotest.(check bool) "identity from incremental digest" true
    (Content_identity.equal incremental_identity
       (Content_identity.of_content "prefixbody"));
  check_error (Content_identity.of_sha256_hex ~sha256_hex:"ABC" ~byte_length:0);
  check_error
    (Content_identity.of_sha256_hex ~sha256_hex:(String.make 64 'a')
       ~byte_length:(-1));
  check_error
    (Content_identity.of_display_hash ~hash:(String.make 64 'a')
       ~byte_length:0)

let test_protocol_integer_domain () =
  let maximum = Protocol_integer.maximum_safe in
  ignore (expect_ok (Text_range.make ~start:maximum ~end_:maximum));
  check_error (Text_range.make ~start:(maximum + 1) ~end_:(maximum + 1));
  let digest = Content_digest.of_content "" in
  ignore (expect_ok (Content_identity.of_digest ~digest ~byte_length:maximum));
  check_error
    (Content_identity.of_digest ~digest ~byte_length:(maximum + 1));
  let field = expect_ok (Selector.Field_name.make "row") in
  ignore
    (expect_ok
       (Selector.Row_filter.make
          [ (field, Selector.Literal.Int Protocol_integer.minimum_safe) ]));
  check_error
    (Selector.Row_filter.make
       [ (field, Selector.Literal.Int (Protocol_integer.maximum_safe + 1)) ]);
  ignore
    (expect_ok
       (Command_result.make ~command:"test"
          ~termination:Command_result.Completed ~effect:Command_result.No_change
          ~summary:[ ("count", Command_result.Count maximum) ] ()));
  check_error
    (Command_result.make ~command:"test"
       ~termination:Command_result.Completed ~effect:Command_result.No_change
       ~summary:[ ("count", Command_result.Count (maximum + 1)) ] ())

let test_schema_visible_utf8 () =
  Alcotest.(check bool) "Unicode scalar UTF-8" true (Utf8.is_valid "日本語");
  Alcotest.(check bool) "invalid leading byte" false (Utf8.is_valid "\255");
  check_error (Identifier.make "bad\255id");
  check_error (Provenance.make ~source:"bad\255source" ());
  let field = expect_ok (Selector.Field_name.make "field") in
  check_error
    (Selector.Row_filter.make
       [ (field, Selector.Literal.String "bad\255value") ]);
  let range = expect_ok (Text_range.make ~start:0 ~end_:0) in
  check_error (Text_edit.make ~range ~replacement:"bad\255replacement");
  check_error
    (Command_result.make ~command:"test"
       ~termination:Command_result.Completed ~effect:Command_result.No_change
       ~summary:[ ("message", Command_result.Text "bad\255summary") ] ())

let test_conflict_construction () =
  let patch_id = expect_ok (Patch_id.make "patch:conflict") in
  let target = expect_ok (Workspace_path.of_canonical_string "file.txt") in
  let identity = Content_identity.of_content "same" in
  check_error
    (Conflict.identity_mismatch ~patch_id ~target ~expected:identity
       ~actual:identity);
  check_error
    (Conflict.result_identity_mismatch ~patch_id ~target ~declared:identity
       ~actual:identity);
  let inside = expect_ok (Text_range.make ~start:0 ~end_:3) in
  let outside = expect_ok (Text_range.make ~start:0 ~end_:4) in
  check_error
    (Conflict.range_out_of_bounds ~patch_id ~target ~range:inside
       ~content_length:3);
  ignore
    (expect_ok
       (Conflict.range_out_of_bounds ~patch_id ~target ~range:outside
          ~content_length:3));
  let separate = expect_ok (Text_range.make ~start:3 ~end_:4) in
  check_error
    (Conflict.overlapping_edits ~patch_id ~target ~left:inside ~right:separate);
  let overlap = expect_ok (Text_range.make ~start:2 ~end_:4) in
  ignore
    (expect_ok
       (Conflict.overlapping_edits ~patch_id ~target ~left:inside
          ~right:overlap))

let sample_patch edits =
  let id = expect_ok (Patch_id.make "patch:one") in
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
       (sample_patch [ expect_ok (Text_edit.make ~range ~replacement:"inserted") ]));
  let id = expect_ok (Patch_id.make "patch:create") in
  let target = expect_ok (Workspace_path.of_segments [ "created.txt" ]) in
  let provenance = expect_ok (Provenance.make ~source:"test" ()) in
  let content = "created\n" in
  ignore
    (expect_ok
       (Proposed_patch.make_create ~id ~target
          ~resulting_identity:(Content_identity.of_content content)
          ~content ~reason:"create test file" ~provenance));
  check_error
    (Proposed_patch.make_create ~id ~target
       ~resulting_identity:(Content_identity.of_content "different")
       ~content ~reason:"create test file" ~provenance)

let test_artifact_origin_and_reference_target () =
  let path =
    expect_ok
      (Workspace_path.of_native_string ~flavor:Workspace_path.Posix
         "runs/metrics.jsonl")
  in
  let workspace = Artifact.workspace path in
  let artifact_id = expect_ok (Artifact_id.make "artifact:metrics") in
  let content_identity = Content_identity.of_content "{}\n" in
  check_error
    (Artifact.make ~id:artifact_id ~origin:workspace ~media_type:""
       ~content_identity ());
  let artifact =
    expect_ok
      (Artifact.make ~id:artifact_id ~origin:workspace
         ~media_type:"application/jsonl" ~content_identity ())
  in
  Alcotest.(check (option string)) "non-empty media type"
    (Some "application/jsonl") (Artifact.media_type artifact);
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
  check_error
    (Reference.make_target ~artifact:workspace
       ~selector:Selector.Whole_artifact ~interpreter:"" ());
  let target =
    expect_ok
      (Reference.make_target ~artifact:workspace
         ~selector:Selector.Whole_artifact ~interpreter:"jsonl" ())
  in
  Alcotest.(check (option string)) "interpreter" (Some "jsonl")
    target.interpreter;
  Alcotest.(check bool) "whole-artifact selector is explicit" true
    (Selector.compare target.selector Selector.Whole_artifact = 0)

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
  let source_artifact = expect_ok (Artifact_id.make "artifact:metrics") in
  let id =
    expect_ok (Reference_id.make ~artifact:source_artifact ~local:"latency-run-a")
  in
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
  let registry =
    [
      (Diagnostic.Sidecar_only, "info");
      (Diagnostic.Inline_only, "warning");
      (Diagnostic.Divergent, "error");
      (Diagnostic.Stale_selector, "error");
      (Diagnostic.Duplicate, "warning");
      (Diagnostic.Unreferenced_ref, "warning");
      (Diagnostic.Unresolved_ref, "error");
      (Diagnostic.Expectation_failed, "error");
      (Diagnostic.Invalid_sidecar, "error");
      (Diagnostic.Invalid_selector, "error");
      (Diagnostic.Unsupported_artifact, "warning");
      (Diagnostic.Unsupported_filesystem_entry, "warning");
    ]
  in
  List.iter
    (fun (code, expected) ->
      Alcotest.(check string)
        ("registry default for " ^ Diagnostic.code_string code)
        expected
        (Diagnostic.default_severity code |> Diagnostic.severity_string))
    registry;
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

let test_capability () =
  check_error
    (Capability.make ~kind:Capability.Interpreter ~name:"" ~version:"1" ());
  check_error
    (Capability.make ~kind:Capability.Interpreter ~name:"markdown"
       ~version:"1"
       ~applies_to:
         Capability.{ media_types = [ "text/markdown"; "text/markdown" ]; path_globs = [] }
       ());
  check_error
    (Capability.make ~kind:Capability.Interpreter ~name:"markdown"
       ~version:"1"
       ~schemas:
         Capability.{ selector = None; annotation = None; options = None }
       ());
  let capability =
    expect_ok
      (Capability.make ~kind:Capability.Interpreter ~name:"markdown"
         ~version:"1"
         ~applies_to:
           Capability.{ media_types = [ "text/markdown" ]; path_globs = [] }
         ())
  in
  check_error
    (Command_result.make ~command:"capabilities"
       ~termination:Command_result.Completed ~effect:Command_result.No_change
       ~capabilities:[ capability; capability ] ())

let test_extension_descriptor () =
  let capability =
    `Assoc
      [
        ("type", `String "interpreter");
        ("name", `String "custom-markdown");
        ("version", `String "1");
        ( "appliesTo",
          `Assoc
            [
              ("mediaTypes", `List [ `String "text/markdown" ]);
              ("pathGlobs", `List []);
            ] );
      ]
  in
  let descriptor =
    expect_ok
      (Extension_descriptor.of_yojson
         (`Assoc
           [ ("protocolVersion", `String "1"); ("capability", capability) ]))
  in
  Alcotest.(check string) "protocol version" "1"
    (Extension_descriptor.protocol_version descriptor);
  Alcotest.(check string) "capability name" "custom-markdown"
    (Extension_descriptor.capability descriptor |> Capability.name);
  check_error
    (Extension_descriptor.of_yojson
       (`Assoc
         [
           ("protocolVersion", `String "1");
           ("protocolVersion", `String "1");
           ("capability", capability);
         ]));
  check_error
    (Extension_descriptor.of_yojson
       (`Assoc
         [ ("protocolVersion", `String "2"); ("capability", capability) ]));
  check_error
    (Extension_descriptor.of_yojson
       (`Assoc
         [
           ("protocolVersion", `String "1");
           ( "capability",
             `Assoc
               [
                 ("type", `String "interpreter");
                 ("name", `String "custom-markdown");
                 ("version", `String "1");
                 ("command", `String "must-not-be-executed");
               ] );
         ]));
  check_error
    (Extension_descriptor.of_yojson
       (`Assoc
         [
           ("protocolVersion", `String "1");
           ("capability", capability);
           ("bad\255field", `Bool true);
         ]))

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
    sample_patch
      [ expect_ok (Text_edit.make ~range:patch_range ~replacement:"new") ]
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
  check_error
    (Command_result.make ~command:"derive"
       ~termination:Command_result.Completed
       ~effect:Command_result.Patches_proposed ~patches:[ patch; patch ] ());
  let applied_result =
    expect_ok
      (Command_result.make ~command:"apply"
         ~termination:Command_result.Completed ~effect:Command_result.Applied
         ~changed_artifacts:
           [ { Command_result.path = changed_path; before = Some before; after } ]
         ())
  in
  Alcotest.(check string) "applied status" "applied"
    (Command_result.status applied_result |> Command_result.status_string);
  let patch_id = Proposed_patch.id patch in
  let conflict =
    expect_ok
      (Conflict.identity_mismatch ~patch_id ~target:changed_path ~expected:before
         ~actual:after)
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
         [ { Command_result.path = changed_path; before = Some before; after } ]
       ());
  check_error
    (Command_result.make ~command:"apply"
       ~termination:Command_result.Completed ~effect:Command_result.Applied
       ~changed_artifacts:
         [ { Command_result.path = changed_path; before = Some before; after } ]
       ~conflicts:[ conflict ] ());
  check_error
    (Command_result.make ~command:"apply"
       ~termination:Command_result.Completed ~effect:Command_result.Conflicted
       ~conflicts:[ conflict ]
       ~changed_artifacts:
         [ { Command_result.path = changed_path; before = Some before; after } ]
       ());
  check_error
    (Command_result.make ~command:"derive"
       ~termination:Command_result.Completed
       ~effect:Command_result.Patches_proposed ~patches:[ patch ]
       ~changed_artifacts:
         [ { Command_result.path = changed_path; before = Some before; after } ]
       ());
  check_error
    (Command_result.make ~command:"apply"
       ~termination:(Command_result.Usage_failure "bad")
       ~effect:Command_result.Applied
       ~changed_artifacts:
         [ { Command_result.path = changed_path; before = Some before; after } ]
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
  let artifact_a = expect_ok (Artifact_id.make "artifact:a") in
  let artifact_b = expect_ok (Artifact_id.make "artifact:b") in
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
    [
      "diagnostics";
      "patches";
      "changedArtifacts";
      "conflicts";
      "snapshots";
      "artifacts";
    ];
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
  expect_ok (Text_edit.make ~range ~replacement)

let workspace_patch ?(id = "patch:test") ~target ~original ~result edits =
  let id = expect_ok (Patch_id.make id) in
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
  let create_content = "created\n" in
  let create =
    expect_ok
      (Proposed_patch.make_create
         ~id:(expect_ok (Patch_id.make "patch:decode-create"))
         ~target:(path "created.txt")
         ~resulting_identity:(Content_identity.of_content create_content)
         ~content:create_content ~reason:"decode create"
         ~provenance:(expect_ok (Provenance.make ~source:"test" ())))
  in
  let create_json = create |> Normal.Patch.normalize |> Normal_json.patch in
  let decoded_create =
    expect_ok (Normal_decode.proposed_patch create_json)
  in
  Alcotest.(check bool) "create patch round trip" true
    (match Proposed_patch.operation decoded_create with
    | Proposed_patch.Create { content } -> String.equal content create_content
    | Proposed_patch.Edit _ -> false);
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
      ("edit with content", add_field "content" (`String "wrong") json);
      ( "create with edits",
        add_field "edits" (`List [])
          create_json );
      ( "create with expected identity",
        add_field "expectedContentIdentity"
          (`Assoc
            [
              ( "hash",
                `String
                  (Content_identity.display_hash
                     (Content_identity.of_content "")) );
              ("size", `Int 0);
            ])
          create_json );
      ("create without content", remove_field "content" create_json);
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
  let escaped = expect_ok (Workspace_path.of_segments [ "\255" ]) in
  let plain = expect_ok (Workspace_path.of_segments [ "z" ]) in
  let arbitrary_bytes =
    expect_ok (Workspace_snapshot.make [ (plain, "plain"); (escaped, "escaped") ])
  in
  Alcotest.(check (list string))
    "arbitrary filename bytes use canonical-string order"
    [ "%FF"; "z" ]
    (Workspace_snapshot.files arbitrary_bytes
    |> List.map (fun file ->
           Workspace_snapshot.file_path file
           |> Workspace_path.to_canonical_string));
  check_error (Workspace_snapshot.make [ (a, "A"); (a, "duplicate") ])

let test_workspace_create_patch () =
  let target = path "created.txt" in
  let content = "created\n" in
  let id = expect_ok (Patch_id.make "patch:create") in
  let provenance = expect_ok (Provenance.make ~source:"test" ()) in
  let patch =
    expect_ok
      (Proposed_patch.make_create ~id ~target
         ~resulting_identity:(Content_identity.of_content content)
         ~content ~reason:"create workspace artifact" ~provenance)
  in
  let empty = expect_ok (Workspace_snapshot.make []) in
  let created =
    match Workspace_ops.apply_patch empty patch with
    | Workspace_ops.Applied applied ->
        Alcotest.(check bool) "create has no before identity" true
          (Option.is_none applied.changed.before);
        applied.snapshot
    | Workspace_ops.No_change _ -> Alcotest.fail "create unexpectedly did nothing"
    | Workspace_ops.Conflict _ -> Alcotest.fail "create unexpectedly conflicted"
  in
  (match Workspace_ops.apply_patch created patch with
  | Workspace_ops.No_change _ -> ()
  | Workspace_ops.Applied _ | Workspace_ops.Conflict _ ->
      Alcotest.fail "reapplying create patch must be a no-op");
  let occupied =
    expect_ok (Workspace_snapshot.make [ (target, "different\n") ])
  in
  match Workspace_ops.apply_patch occupied patch with
  | Workspace_ops.Conflict (Conflict.Artifact_already_exists _) -> ()
  | Workspace_ops.Applied _ | Workspace_ops.No_change _
  | Workspace_ops.Conflict _ ->
      Alcotest.fail "create must conflict with different existing content"

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

let sidecar_context () =
  let primary_artifact = expect_ok (Artifact_id.make "artifact:docs/note.md") in
  let sidecar_artifact =
    expect_ok (Artifact_id.make "artifact:docs/note.annotations.yaml")
  in
  let sidecar_path = path "docs/note.annotations.yaml" in
  (primary_artifact, sidecar_artifact, sidecar_path)

let decode_sidecar content =
  let primary_artifact, sidecar_artifact, sidecar_path = sidecar_context () in
  Sidecar_v1.decode ~primary_artifact ~sidecar_artifact ~sidecar_path content

let valid_sidecar =
  {|version: 1
derived:
  refs: {}
  annotations: {}
authored:
  refs:
    run-a:
      target:
        artifact:
          origin:
            kind: workspace
            path: runs/data.jsonl
        selector:
          kind: row-filter
          where:
            metric: latency
            attempt: 1
        interpreter: jsonl
      binding:
        mode: pinned
      expect:
        - digest: sha256:aafdf097b034d51e1794cb111ce16c46f88e9ef17da6f859a00fd39288e69ef6
  annotations:
    supported:
      subject:
        artifact:
          origin:
            kind: workspace
            path: docs/note.md
        selector:
          kind: region-id
          id: claim
        interpreter: markdown
      predicate: supported-by
      object:
        ref: run-a
|}

let test_sidecar_v1_strict_decode () =
  let decoded = expect_ok (decode_sidecar valid_sidecar) in
  Alcotest.(check int) "reference count" 1 (List.length decoded.references);
  Alcotest.(check int) "annotation count" 1 (List.length decoded.annotations);
  let reference = List.hd decoded.references in
  Alcotest.(check string) "scoped reference local ID" "run-a"
    (Reference.id reference |> Reference_id.local |> Identifier.to_string);
  match Reference.target_selector (Reference.target reference) with
  | Selector.Row_filter filter ->
      Alcotest.(check int) "row-filter conditions" 2
        (List.length (Selector.Row_filter.conditions filter))
  | _ -> Alcotest.fail "expected a row-filter selector"

let test_sidecar_annotation_insertion_offset () =
  let range = expect_ok (Sidecar_edit.derived_section_range valid_sidecar) in
  let selected =
    String.sub valid_sidecar (Text_range.start range) (Text_range.length range)
  in
  Alcotest.(check string) "derived section range"
    "derived:\n  refs: {}\n  annotations: {}\n"
    selected;
  let unicode =
    "version: 1\nderived:\n  refs: {}\n  annotations: {}\nauthored:\n  refs: {日本語: {}}\n"
  in
  let range = expect_ok (Sidecar_edit.derived_section_range unicode) in
  Alcotest.(check string) "YAML character mark converts to byte offset"
    "derived:\n  refs: {}\n  annotations: {}\n"
    (String.sub unicode (Text_range.start range) (Text_range.length range));
  Alcotest.(check bool) "missing derived section" true
    (Option.is_none
       (expect_ok
          (Sidecar_edit.optional_derived_section_range
             "version: 1\nauthored: {refs: {}, annotations: {}}\n")))

let test_sidecar_authored_overrides_derived () =
  let decoded =
    expect_ok
      (decode_sidecar
         {|version: 1
derived:
  refs:
    run-a:
      target:
        artifact:
          origin:
            kind: workspace
            path: runs/derived.jsonl
        selector:
          kind: region-id
          id: derived
      binding:
        mode: tracking
  annotations: {}
authored: {refs: {run-a: {target: {artifact: {origin: {kind: workspace, path: runs/authored.jsonl}}, selector: {kind: region-id, id: authored}}, binding: {mode: pinned}}}, annotations: {}}
|})
  in
  Alcotest.(check int) "one effective reference" 1
    (List.length decoded.references);
  let selected = List.hd decoded.references in
  Alcotest.(check string) "authored reference wins" "runs/authored.jsonl"
    (match Reference.target_artifact (Reference.target selected) with
    | Artifact.Workspace path -> Workspace_path.to_canonical_string path
    | _ -> Alcotest.fail "expected workspace target");
  Alcotest.(check int) "override is observable" 1
    (List.length decoded.overrides)

let test_sidecar_layout_profile () =
  ignore
    (expect_ok
       (decode_sidecar
          "version: 1\nauthored: {refs: {}, annotations: {}}\n"));
  check_error
    (decode_sidecar
       "version: 1\nderived: {refs: {}, annotations: {}}\nauthored: {}\n");
  check_error
    (decode_sidecar
       "{version: 1, derived: {refs: {}, annotations: {}}, authored: {}}\n");
  check_error
    (Sidecar_edit.validate_layout_profile
       "version: 1\nderived:\n  refs:\n    item: {target: {}, binding: {}}\n  annotations: {}\nauthored: {}\n")

let test_sidecar_v1_rejects_yaml_ambiguity () =
  let replace needle replacement content =
    let start =
      match Str.search_forward (Str.regexp_string needle) content 0 with
      | index -> index
      | exception Not_found -> Alcotest.fail "test fixture replacement failed"
    in
    String.sub content 0 start ^ replacement
    ^ String.sub content (start + String.length needle)
        (String.length content - start - String.length needle)
  in
  ignore (expect_ok (decode_sidecar (replace "metric: latency" "metric: latency.p95" valid_sidecar)));
  check_error
    (decode_sidecar
       (replace "refs:" "refs:\n  duplicate: &shared {}\n  alias: *shared" valid_sidecar));
  check_error
    (decode_sidecar
       (replace "version: 1" "version: 1\nversion: 1" valid_sidecar));
  check_error
    (decode_sidecar
       (replace "attempt: 1" "attempt: 1.5" valid_sidecar));
  check_error
    (decode_sidecar
       (replace "metric: latency" "metric: !!str latency" valid_sidecar));
  check_error
    (decode_sidecar
       (replace "binding:" "procedure: run-this\n    binding:" valid_sidecar))

let test_workspace_read_regular_file () =
  with_temp_workspace (fun root ->
      Unix.mkdir (Filename.concat root "docs") 0o700;
      write_file (Filename.concat root "docs/note.md") "日本語\n";
      let path = path "docs/note.md" in
      match Workspace_read.read ~workspace:root ~path with
      | Error _ -> Alcotest.fail "workspace read failed"
      | Ok file ->
          Alcotest.(check string) "content" "日本語\n"
            (Workspace_read.content file);
          Alcotest.(check bool) "content identity" true
            (Content_identity.equal (Content_identity.of_content "日本語\n")
               (Workspace_read.content_identity file)))

let test_workspace_read_rejects_symlink () =
  if not Sys.win32 then
    with_temp_workspace (fun root ->
        write_file (Filename.concat root "target.md") "outside semantic path";
        Unix.symlink "target.md" (Filename.concat root "link.md");
        match Workspace_read.read ~workspace:root ~path:(path "link.md") with
        | Error (Workspace_read.Unsafe Workspace_read.Symlink_component) -> ()
        | Error _ -> Alcotest.fail "unexpected workspace read error"
        | Ok _ -> Alcotest.fail "workspace read followed a symbolic link")

let markdown_fixture =
  {|# Fixture

<!-- monika:region id=claim -->

The claim uses [run \[A\]](../runs/data.jsonl#run-a).

<!-- monika:annotation id=evidence predicate=supported-by ref=run-a -->
|}

let test_workspace_inspect_authored_priority () =
  with_temp_workspace (fun root ->
      Unix.mkdir (Filename.concat root "docs") 0o700;
      write_file (Filename.concat root "docs/note.md") markdown_fixture;
      write_file
        (Filename.concat root "docs/note.annotations.yaml")
        {|version: 1
derived:
  refs:
    run-a:
      target:
        artifact:
          origin:
            kind: workspace
            path: runs/data.jsonl
        selector:
          kind: region-id
          id: run-a
      binding:
        mode: floating
  annotations: {}
authored:
  refs:
    run-a:
      target:
        artifact:
          origin:
            kind: workspace
            path: runs/authored.jsonl
        selector:
          kind: region-id
          id: selected
      binding:
        mode: pinned
  annotations:
    evidence:
      subject:
        artifact:
          origin:
            kind: workspace
            path: docs/note.md
        selector:
          kind: region-id
          id: claim
        interpreter: markdown
      predicate: user-selected
      object:
        ref: run-a
|};
      let result =
        Workspace_inspect.inspect ~workspace:root ~artifact:(path "docs/note.md")
      in
      Alcotest.(check string) "inspection completes" "diagnostics-found"
        (result_status result);
      let reference = List.hd (Command_result.references result) in
      Alcotest.(check string) "authored reference has complete-record priority"
        "runs/authored.jsonl"
        (match Reference.target_artifact (Reference.target reference) with
      | Artifact.Workspace target ->
            Workspace_path.to_canonical_string target
        | _ -> Alcotest.fail "expected a workspace reference");
      let annotation =
        List.find
          (fun annotation ->
            String.equal
              (Annotation.id annotation |> Annotation_id.local
             |> Identifier.to_string)
              "evidence")
          (Command_result.annotations result)
      in
      Alcotest.(check string) "authored annotation has priority"
        "user-selected" (Annotation.predicate annotation);
      Alcotest.(check int) "both materialization surfaces remain observable" 2
        (List.length (Annotation.materialization annotation));
      let codes =
        Command_result.diagnostics result |> List.map Diagnostic.code
      in
      Alcotest.(check bool) "derived override is observable" true
        (List.mem Diagnostic.Authored_override codes);
      Alcotest.(check bool) "inline disagreement is observable" true
        (List.mem Diagnostic.Divergent codes))

let test_workspace_derive_create_apply_idempotent () =
  with_temp_workspace (fun root ->
      Unix.mkdir (Filename.concat root "docs") 0o700;
      write_file (Filename.concat root "docs/note.md") markdown_fixture;
      let first =
        Workspace_derive.derive_sidecar ~workspace:root
          ~artifact:(path "docs/note.md")
      in
      Alcotest.(check string) "missing sidecar proposes create"
        "patches-proposed" (result_status first);
      let patch =
        match Command_result.patches first with
        | [ patch ] -> patch
        | _ -> Alcotest.fail "derive must propose exactly one create patch"
      in
      Alcotest.(check bool) "derive uses a create patch" true
        (match Proposed_patch.operation patch with
        | Proposed_patch.Create _ -> true
        | Proposed_patch.Edit _ -> false);
      let applied =
        Filesystem_apply.apply ~workspace:root ~patch ~dry_run:false
      in
      Alcotest.(check string) "create patch applies" "applied"
        (result_status applied);
      let sidecar =
        read_file (Filename.concat root "docs/note.annotations.yaml")
      in
      Alcotest.(check bool) "new sidecar owns a derived section" true
        (String.starts_with ~prefix:"version: 1\nderived:\n" sidecar);
      Alcotest.(check bool) "new sidecar includes an authored section" true
        (try
           ignore
             (Str.search_forward
                (Str.regexp_string
                   "authored:\n  refs: {}\n  annotations: {}\n")
                sidecar 0);
           true
         with Not_found -> false);
      let second =
        Workspace_derive.derive_sidecar ~workspace:root
          ~artifact:(path "docs/note.md")
      in
      Alcotest.(check string) "derive after apply is valid" "ok"
        (result_status second);
      Alcotest.(check bool) "derive after apply has no effect" true
        (Command_result.effect second = Command_result.No_change);
      Alcotest.(check int) "no repeated patch" 0
        (List.length (Command_result.patches second)))

let test_workspace_derive_preserves_authored_bytes () =
  with_temp_workspace (fun root ->
      Unix.mkdir (Filename.concat root "docs") 0o700;
      write_file (Filename.concat root "docs/note.md") markdown_fixture;
      let authored =
        "authored: {refs: {}, annotations: {}}\n"
      in
      write_file
        (Filename.concat root "docs/note.annotations.yaml")
        ("version: 1\n" ^ authored);
      let derived =
        Workspace_derive.derive_sidecar ~workspace:root
          ~artifact:(path "docs/note.md")
      in
      let patch =
        match Command_result.patches derived with
        | [ patch ] -> patch
        | _ -> Alcotest.fail "derive must propose one edit patch"
      in
      Alcotest.(check bool) "existing sidecar uses an edit patch" true
        (match Proposed_patch.operation patch with
        | Proposed_patch.Edit _ -> true
        | Proposed_patch.Create _ -> false);
      let applied =
        Filesystem_apply.apply ~workspace:root ~patch ~dry_run:false
      in
      Alcotest.(check string) "edit patch applies" "applied"
        (result_status applied);
      let content =
        read_file (Filename.concat root "docs/note.annotations.yaml")
      in
      let authored_start =
        Str.search_forward (Str.regexp_string authored) content 0
      in
      Alcotest.(check string) "authored bytes remain exact" authored
        (String.sub content authored_start (String.length authored)));
  with_temp_workspace (fun root ->
      Unix.mkdir (Filename.concat root "docs") 0o700;
      write_file (Filename.concat root "docs/note.md") markdown_fixture;
      let authored =
        "authored:\n"
        ^ "  # This region belongs to the user.\n"
        ^ "  refs: {}\n"
        ^ "  annotations: {\"手書き\": {subject: {artifact: {origin: {kind: workspace, path: docs/note.md}}, selector: {kind: region-id, id: claim}}, predicate: \"備考\", object: {ref: run-a}}}\n"
      in
      write_file
        (Filename.concat root "docs/note.annotations.yaml")
        ("version: 1\n"
        ^ "derived:\n  refs: {}\n  annotations: {}\n"
        ^ authored);
      let derived =
        Workspace_derive.derive_sidecar ~workspace:root
          ~artifact:(path "docs/note.md")
      in
      let patch =
        match Command_result.patches derived with
        | [ patch ] -> patch
        | _ -> Alcotest.fail "derive must replace the existing derived section"
      in
      let applied =
        Filesystem_apply.apply ~workspace:root ~patch ~dry_run:false
      in
      Alcotest.(check string) "derived replacement applies" "applied"
        (result_status applied);
      let content =
        read_file (Filename.concat root "docs/note.annotations.yaml")
      in
      let authored_start =
        Str.search_forward (Str.regexp_string authored) content 0
      in
      Alcotest.(check string)
        "derived replacement preserves authored comments, flow style, and UTF-8"
        authored
        (String.sub content authored_start (String.length authored)))

let test_markdown_inspect_commonmark () =
  let artifact = expect_ok (Artifact_id.make "artifact:docs/note.md") in
  let inspected =
    expect_ok
      (Markdown_inspect.inspect ~artifact ~path:(path "docs/note.md")
         markdown_fixture)
  in
  Alcotest.(check int) "region count" 1 (List.length inspected.regions);
  Alcotest.(check int) "reference count" 1 (List.length inspected.references);
  Alcotest.(check int) "annotation count" 1
    (List.length inspected.annotations);
  let region = List.hd inspected.regions in
  Alcotest.(check string) "region ID" "claim"
    (Region.id region |> Region_id.local |> Identifier.to_string);
  let reference = List.hd inspected.references in
  Alcotest.(check string) "link fragment is reference ID" "run-a"
    (Reference.id reference |> Reference_id.local |> Identifier.to_string);
  (match Reference.target_artifact (Reference.target reference) with
  | Artifact.Workspace target ->
      Alcotest.(check string) "relative link target" "runs/data.jsonl"
        (Workspace_path.to_canonical_string target)
  | _ -> Alcotest.fail "expected a workspace link target");
  let annotation = List.hd inspected.annotations in
  match Annotation.subject annotation with
  | Annotation.Region (Region_ref.Resolved subject) ->
      Alcotest.(check bool) "annotation resolves preceding region" true
        (Region_id.equal subject (Region.id region))
  | _ -> Alcotest.fail "expected a resolved region subject"

let test_markdown_reference_occurrences () =
  let artifact = expect_ok (Artifact_id.make "artifact:docs/source.md") in
  let content =
    {|<!-- monika:region id=claim -->

The claim links to [the whole file](../target.md) and [a named target](../target.md#target-region).
|}
  in
  let inspected =
    expect_ok
      (Markdown_inspect.inspect ~artifact ~path:(path "docs/source.md") content)
  in
  Alcotest.(check int) "reference declaration count" 1
    (List.length inspected.references);
  Alcotest.(check int) "reference occurrence count" 2
    (List.length inspected.occurrences);
  let region = List.hd inspected.regions in
  List.iter
    (fun occurrence ->
      match Reference_occurrence.source_region occurrence with
      | Some source ->
          Alcotest.(check bool) "occurrence belongs to containing region" true
            (Region_id.equal source (Region.id region))
      | None -> Alcotest.fail "expected a containing source region")
    inspected.occurrences;
  let direct =
    List.find
      (fun occurrence ->
        match Reference_occurrence.target occurrence with
        | Reference_occurrence.Direct _ -> true
        | Reference_occurrence.Named _ -> false)
      inspected.occurrences
  in
  (match Reference_occurrence.target direct with
  | Reference_occurrence.Direct address -> (
      match Region_address.artifact address with
      | Artifact.Workspace target ->
          Alcotest.(check string) "direct target path" "target.md"
            (Workspace_path.to_canonical_string target)
      | _ -> Alcotest.fail "expected a workspace target")
  | Reference_occurrence.Named _ ->
      Alcotest.fail "expected a direct occurrence");
  let named =
    List.find
      (fun occurrence ->
        match Reference_occurrence.target occurrence with
        | Reference_occurrence.Named _ -> true
        | Reference_occurrence.Direct _ -> false)
      inspected.occurrences
  in
  match Reference_occurrence.target named with
  | Reference_occurrence.Named id ->
      Alcotest.(check string) "named occurrence reference ID" "target-region"
        (Reference_id.local id |> Identifier.to_string)
  | Reference_occurrence.Direct _ ->
      Alcotest.fail "expected a named occurrence"

let test_relation_projection_from_annotation () =
  let artifact = expect_ok (Artifact_id.make "artifact:docs/note.md") in
  let inspected =
    expect_ok
      (Markdown_inspect.inspect ~artifact ~path:(path "docs/note.md")
         markdown_fixture)
  in
  let annotation = List.hd inspected.annotations in
  match Relation.of_annotation annotation with
  | None -> Alcotest.fail "reference-valued annotation must project a relation"
  | Some relation ->
      Alcotest.(check string) "relation predicate" "supported-by"
        (Relation.predicate relation);
      (match Relation.object_ relation with
      | Relation.Reference id ->
          Alcotest.(check string) "relation reference endpoint" "run-a"
            (Reference_id.local id |> Identifier.to_string)
      | Relation.Region _ ->
          Alcotest.fail "expected a reference relation endpoint")

let test_workspace_graph_related_query () =
  with_temp_workspace (fun root ->
      let source =
        {|<!-- monika:region id=claim -->

See [the target](target.md) and [the named target](target.md#target-region).

<!-- monika:annotation id=evidence predicate=supported-by ref=target-region -->
|}
      in
      let target =
        {|<!-- monika:region id=target-region -->

Target evidence.
|}
      in
      write_file (Filename.concat root "source.md") source;
      write_file (Filename.concat root "target.md") target;
      let expect_query = function
        | Ok result -> result
        | Error (Workspace_graph.Usage message)
        | Error (Workspace_graph.Internal message) ->
            Alcotest.fail ("workspace graph query failed: " ^ message)
      in
      let related =
        expect_query
          (Workspace_graph.query ~workspace:root ~artifact:(path "target.md")
             ~direction:Workspace_graph.Both ~predicate:None ~limit:50)
      in
      Alcotest.(check int) "incoming occurrence and relation count" 3
        (List.length (Workspace_graph.matches related));
      List.iter
        (fun edge ->
          Alcotest.(check bool) "target query edge direction" true
            (match Workspace_graph.direction edge with
            | Workspace_graph.Incoming_edge -> true
            | Workspace_graph.Outgoing_edge | Workspace_graph.Internal_edge ->
                false);
          Alcotest.(check bool) "target resolves" true
            (match Workspace_graph.target_resolution edge with
            | Workspace_graph.Resolved -> true
            | Workspace_graph.Unresolved
            | Workspace_graph.Invalid_selector
            | Workspace_graph.Unreadable
            | Workspace_graph.Not_checked ->
                false))
        (Workspace_graph.matches related);
      let coverage = Workspace_graph.coverage related in
      Alcotest.(check int) "scanned artifacts" 2 coverage.scanned_artifacts;
      Alcotest.(check int) "interpreted artifacts" 2
        coverage.interpreted_artifacts;
      Alcotest.(check bool) "complete coverage" true coverage.complete;
      let limited =
        expect_query
          (Workspace_graph.query ~workspace:root ~artifact:(path "target.md")
             ~direction:Workspace_graph.Both ~predicate:None ~limit:2)
      in
      Alcotest.(check int) "limit" 2
        (List.length (Workspace_graph.matches limited));
      Alcotest.(check bool) "truncation is explicit" true
        (Workspace_graph.truncated limited))

let test_markdown_inspect_rejects_invalid_directives () =
  let artifact = expect_ok (Artifact_id.make "artifact:docs/note.md") in
  let inspect content =
    Markdown_inspect.inspect ~artifact ~path:(path "docs/note.md") content
  in
  check_error (inspect "<!-- monika:region id=one id=two -->\n\ntext\n");
  check_error (inspect "<!-- monika:region name=one -->\n\ntext\n");
  check_error (inspect "<!-- monika:unknown id=one -->\n");
  check_error
    (inspect
       "<!-- monika:annotation id=one predicate=p ref=r -->\n");
  check_error
    (inspect
       "<!-- monika:region id=same -->\n\none\n\n<!-- monika:region id=same -->\n\ntwo\n");
  check_error
    (inspect
       "<!-- monika:region id=region -->\n\ntext\n\n<!-- monika:annotation id=same predicate=p ref=r -->\n\n<!-- monika:annotation id=same predicate=p ref=r -->\n")

let jsonl_filter conditions =
  conditions
  |> List.map (fun (name, value) ->
         (expect_ok (Selector.Field_name.make name), value))
  |> Selector.Row_filter.make |> expect_ok

let test_jsonl_row_filter () =
  let filter =
    jsonl_filter
      [
        ("metric", Selector.Literal.String "latency");
        ("attempt", Selector.Literal.Int 1);
        ("warm", Selector.Literal.Bool true);
      ]
  in
  let content =
    "{\"metric\":\"latency\",\"attempt\":1,\"warm\":true}\n"
    ^ "{\"metric\":\"throughput\",\"attempt\":1,\"warm\":true}\n"
  in
  match expect_ok (Jsonl_interpreter.select filter content) with
  | Jsonl_interpreter.One selected ->
      Alcotest.(check int) "selected start" 0
        (Text_range.start selected.range);
      Alcotest.(check string) "selected display"
        "{\"metric\":\"latency\",\"attempt\":1,\"warm\":true}"
        selected.display
  | Jsonl_interpreter.No_match | Jsonl_interpreter.Ambiguous ->
      Alcotest.fail "expected one JSONL row"

let test_jsonl_row_filter_failures () =
  let filter =
    jsonl_filter [ ("metric", Selector.Literal.String "latency") ]
  in
  Alcotest.(check bool) "no match" true
    (match
       expect_ok
         (Jsonl_interpreter.select filter "{\"metric\":\"throughput\"}\n")
     with
    | Jsonl_interpreter.No_match -> true
    | _ -> false);
  Alcotest.(check bool) "ambiguous" true
    (match
       expect_ok
         (Jsonl_interpreter.select filter
            "{\"metric\":\"latency\"}\n{\"metric\":\"latency\"}\n")
     with
    | Jsonl_interpreter.Ambiguous -> true
    | _ -> false);
  check_error
    (Jsonl_interpreter.select filter
       "{\"metric\":\"latency\",\"metric\":\"throughput\"}\n");
  check_error (Jsonl_interpreter.select filter "[1,2,3]\n");
  check_error (Jsonl_interpreter.select filter "{bad json}\n")

let test_resolve_observation_time () =
  Alcotest.(check string) "canonical UTC timestamp" "2026-07-17T00:00:00Z"
    (expect_ok
       (Workspace_resolve.canonical_observed_at "2026-07-17T00:00:00Z"));
  check_error
    (Workspace_resolve.canonical_observed_at "2026-07-17T09:00:00+09:00");
  check_error (Workspace_resolve.canonical_observed_at "now")

let check_filesystem_apply_result ~status ~exit_class result =
  Alcotest.(check string) "status" status (result_status result);
  Alcotest.(check string) "exitClass" exit_class (result_exit_class result)

let filesystem_create_patch ~target content =
  let id = expect_ok (Patch_id.make "patch:filesystem-create") in
  let provenance = expect_ok (Provenance.make ~source:"test" ()) in
  expect_ok
    (Proposed_patch.make_create ~id ~target
       ~resulting_identity:(Content_identity.of_content content)
       ~content ~reason:"filesystem create test" ~provenance)

let test_filesystem_apply_create () =
  with_temp_workspace (fun root ->
      let target = path "created.txt" in
      let native = Filename.concat root "created.txt" in
      let patch = filesystem_create_patch ~target "created\n" in
      let dry_run =
        Filesystem_apply.apply ~workspace:root ~patch ~dry_run:true
      in
      check_filesystem_apply_result ~status:"patches-proposed"
        ~exit_class:"success" dry_run;
      Alcotest.(check bool) "dry-run does not create" false
        (Sys.file_exists native);
      let applied =
        Filesystem_apply.apply ~workspace:root ~patch ~dry_run:false
      in
      check_filesystem_apply_result ~status:"applied" ~exit_class:"success"
        applied;
      Alcotest.(check string) "created content" "created\n"
        (read_file native);
      let repeated =
        Filesystem_apply.apply ~workspace:root ~patch ~dry_run:false
      in
      check_filesystem_apply_result ~status:"ok" ~exit_class:"success"
        repeated);
  with_temp_workspace (fun root ->
      let target = path "created.txt" in
      let native = Filename.concat root "created.txt" in
      write_file native "occupied\n";
      let patch = filesystem_create_patch ~target "created\n" in
      let conflicted =
        Filesystem_apply.apply ~workspace:root ~patch ~dry_run:false
      in
      check_filesystem_apply_result ~status:"conflict"
        ~exit_class:"diagnostic-error" conflicted;
      Alcotest.(check string) "conflict preserves existing file" "occupied\n"
        (read_file native))

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
        let expected_mode = (Unix.stat file).Unix.st_perm land 0o7777 in
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
        Alcotest.(check int) "preserves source mode" expected_mode mode)

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

let try_windows_junction target link =
  let null = Unix.openfile "NUL" [ Unix.O_WRONLY ] 0 in
  Fun.protect
    ~finally:(fun () -> Unix.close null)
    (fun () ->
      try
        let process =
          Unix.create_process "cmd.exe"
            [| "cmd.exe"; "/d"; "/c"; "mklink"; "/J"; link; target |]
            Unix.stdin null null
        in
        match snd (Unix.waitpid [] process) with Unix.WEXITED 0 -> true | _ -> false
      with Unix.Unix_error _ -> false)

let try_directory_symlink target link =
  try
    Unix.symlink ~to_dir:true target link;
    true
  with
  | Unix.Unix_error ((Unix.EPERM | Unix.EACCES), _, _) when Sys.win32 ->
      try_windows_junction target link

let test_filesystem_apply_native_spelling () =
  let check_folded_lookup root ~stored ~alternate =
    let stored_path = Filename.concat root stored in
    let alternate_path = Filename.concat root alternate in
    if
      not (String.equal stored alternate)
      && Sys.file_exists alternate_path
    then
      let target = expect_ok (Workspace_path.of_segments [ alternate ]) in
      let patch =
        workspace_patch ~target ~original:"abc" ~result:"ABC"
          [ edit 0 3 "ABC" ]
      in
      let result =
        Filesystem_apply.apply ~workspace:root ~patch ~dry_run:false
      in
      check_filesystem_apply_result ~status:"conflict"
        ~exit_class:"diagnostic-error" result;
      Alcotest.(check (option string)) "native spelling conflict"
        (Some "native-spelling-mismatch")
        (filesystem_safety_reason result);
      Alcotest.(check string) "folded lookup does not rewrite stored entry" "abc"
        (read_file stored_path)
  in
  with_temp_workspace (fun root ->
      write_file (Filename.concat root "Case.txt") "abc";
      check_folded_lookup root ~stored:"Case.txt" ~alternate:"case.txt");
  with_temp_workspace (fun root ->
      let composed = "\xC3\xA9.txt" in
      let decomposed = "e\xCC\x81.txt" in
      write_file (Filename.concat root composed) "abc";
      let entries = Sys.readdir root in
      if Array.length entries <> 1 then
        Alcotest.fail "normalization test workspace has unexpected entries";
      let stored = entries.(0) in
      let alternate =
        if String.equal stored composed then decomposed else composed
      in
      check_folded_lookup root ~stored ~alternate)

let test_windows_reparse_point_boundary () =
  if Sys.win32 then
    with_temp_workspace (fun enclosing_root ->
        let workspace = Filename.concat enclosing_root "workspace" in
        let outside = Filename.concat enclosing_root "outside" in
        Unix.mkdir workspace 0o700;
        Unix.mkdir outside 0o700;
        write_file (Filename.concat outside "file.txt") "outside";
        let link = Filename.concat workspace "linked" in
        if try_directory_symlink outside link then (
          let target = expect_ok (Workspace_path.of_segments [ "linked"; "file.txt" ]) in
          let patch =
            workspace_patch ~target ~original:"outside" ~result:"changed"
              [ edit 0 7 "changed" ]
          in
          let result =
            Filesystem_apply.apply ~workspace ~patch ~dry_run:false
          in
          check_filesystem_apply_result ~status:"conflict"
            ~exit_class:"diagnostic-error" result;
          Alcotest.(check (option string)) "reparse-point conflict"
            (Some "reparse-point") (filesystem_safety_reason result);
          Alcotest.(check string) "reparse target remains unchanged" "outside"
            (read_file (Filename.concat outside "file.txt"));
          let scan = Workspace_scan.scan ~workspace in
          Alcotest.(check string) "reparse scan status" "diagnostics-found"
            (result_status scan);
          Alcotest.(check int) "reparse is not scanned" 0
            (List.length (Command_result.artifacts scan))))

let read_descriptor fd =
  let input = Unix.in_channel_of_descr fd in
  Fun.protect
    ~finally:(fun () -> close_in_noerr input)
    (fun () -> really_input_string input (in_channel_length input))

let write_descriptor fd content =
  let rec loop offset =
    if offset < String.length content then
      let written =
        Unix.write_substring fd content offset (String.length content - offset)
      in
      if written = 0 then failwith "descriptor write made no progress"
      else loop (offset + written)
  in
  loop 0

let test_handle_boundary_holds_parent_descriptor () =
  with_temp_workspace (fun enclosing_root ->
        let workspace = Filename.concat enclosing_root "workspace" in
        let outside = Filename.concat enclosing_root "outside" in
        Unix.mkdir workspace 0o700;
        Unix.mkdir outside 0o700;
        let original_parent = Filename.concat workspace "parent" in
        let moved_parent = Filename.concat workspace "parent-moved" in
        Unix.mkdir original_parent 0o700;
        write_file (Filename.concat original_parent "file.txt") "inside";
        write_file (Filename.concat outside "file.txt") "outside";
        let root_fd = Filesystem_handle.open_root workspace in
        Fun.protect
          ~finally:(fun () -> Unix.close root_fd)
          (fun () ->
            let parent_fd = Filesystem_handle.open_dir_at root_fd "parent" in
            Fun.protect
              ~finally:(fun () -> Unix.close parent_fd)
              (fun () ->
                Unix.rename original_parent moved_parent;
                if try_directory_symlink outside original_parent then (
                  let file_fd =
                    Filesystem_handle.open_regular_at parent_fd "file.txt"
                  in
                  Alcotest.(check string)
                    "read remains attached to opened parent"
                    "inside" (read_descriptor file_fd);
                  let temp_fd =
                    Filesystem_handle.create_exclusive_at parent_fd
                      ".replacement" 0o600
                  in
                  Fun.protect
                    ~finally:(fun () -> Unix.close temp_fd)
                    (fun () ->
                      write_descriptor temp_fd "updated";
                      Unix.fsync temp_fd);
                  Filesystem_handle.rename_at parent_fd ".replacement" parent_fd
                    "file.txt";
                  Alcotest.(check string)
                    "replacement remains attached to opened parent"
                    "updated" (read_file (Filename.concat moved_parent "file.txt"));
                  Alcotest.(check string) "outside file is unchanged" "outside"
                    (read_file (Filename.concat outside "file.txt"))))))

let filesystem_commit_stage_string = function
  | Filesystem_commit.Prepare_temporary -> "prepare-temporary"
  | Filesystem_commit.Verify_source -> "verify-source"
  | Filesystem_commit.Atomic_replace -> "atomic-replace"
  | Filesystem_commit.Flush_parent -> "flush-parent"
  | Filesystem_commit.Verify_result -> "verify-result"

let filesystem_commit_state_string = function
  | Filesystem_commit.Not_committed -> "not-committed"
  | Filesystem_commit.Committed_or_unknown -> "committed-or-unknown"

let test_filesystem_commit_faults () =
  let run failing_stage =
    let calls = ref [] in
    let cleaned = ref false in
    let operation stage value =
      calls := !calls @ [ stage ];
      if stage = failing_stage then Error stage else Ok value
    in
    let operations : (string, string) Filesystem_commit.operations =
      {
        prepare_temporary =
          (fun () -> operation "prepare-temporary" "temporary");
        cleanup_temporary =
          (fun temporary ->
            Alcotest.(check string) "cleanup target" "temporary" temporary;
            cleaned := true);
        verify_source = (fun () -> operation "verify-source" ());
        atomic_replace =
          (fun temporary ->
            Alcotest.(check string) "replace target" "temporary" temporary;
            operation "atomic-replace" ());
        flush_parent = (fun () -> operation "flush-parent" ());
        verify_result = (fun () -> operation "verify-result" ());
      }
    in
    match Filesystem_commit.run operations with
    | Ok () -> Alcotest.fail "injected commit failure unexpectedly succeeded"
    | Error failure -> (failure, !calls, !cleaned)
  in
  List.iter
    (fun (stage, expected_state, expected_cleanup) ->
      let failure, calls, cleaned = run stage in
      Alcotest.(check string) "failure stage" stage
        (filesystem_commit_stage_string failure.stage);
      Alcotest.(check string) "commit state" expected_state
        (filesystem_commit_state_string failure.commit_state);
      Alcotest.(check string) "preserved cause" stage failure.cause;
      Alcotest.(check bool) "temporary cleanup" expected_cleanup cleaned;
      Alcotest.(check bool) "stops at failed operation" true
        (List.hd (List.rev calls) = stage))
    [
      ("prepare-temporary", "not-committed", false);
      ("verify-source", "not-committed", true);
      ("atomic-replace", "committed-or-unknown", true);
      ("flush-parent", "committed-or-unknown", false);
      ("verify-result", "committed-or-unknown", false);
    ]

let test_stable_read_mutation_retry () =
  let observations =
    ref
      [
        Filesystem_stable_read.Changed;
        Filesystem_stable_read.Stable "stable";
      ]
  in
  let attempts = ref 0 in
  let attempt () =
    incr attempts;
    match !observations with
    | [] -> Alcotest.fail "stable read performed an extra attempt"
    | observation :: rest ->
        observations := rest;
        Ok observation
  in
  Alcotest.(check (result string string)) "one mutation is retried" (Ok "stable")
    (Filesystem_stable_read.retry ~attempts:2 ~on_unstable:"unstable" attempt);
  Alcotest.(check int) "two attempts" 2 !attempts;
  attempts := 0;
  let always_changed () =
    incr attempts;
    Ok Filesystem_stable_read.Changed
  in
  Alcotest.(check (result string string)) "repeated mutation fails"
    (Error "unstable")
    (Filesystem_stable_read.retry ~attempts:2 ~on_unstable:"unstable"
       always_changed);
  Alcotest.(check int) "retry remains bounded" 2 !attempts

let artifact_paths result =
  result |> Command_result.artifacts
  |> List.map (fun artifact ->
         Artifact.origin artifact |> function
         | Artifact.Workspace path -> Workspace_path.to_canonical_string path
         | _ -> Alcotest.fail "expected workspace artifact")
  |> List.sort String.compare

let test_workspace_scan_regular_files () =
  with_temp_workspace (fun root ->
      Unix.mkdir (Filename.concat root "docs") 0o700;
      write_file (Filename.concat root "b.txt") "b";
      write_file (Filename.concat root "a.txt") "a";
      write_file (Filename.concat (Filename.concat root "docs") "note.md") "# Note\n";
      let result = Workspace_scan.scan ~workspace:root in
      Alcotest.(check string) "status" "ok" (result_status result);
      Alcotest.(check string) "exitClass" "success" (result_exit_class result);
      Alcotest.(check (list string)) "stable artifact paths"
        [ "a.txt"; "b.txt"; "docs/note.md" ]
        (artifact_paths result);
      Alcotest.(check int) "artifact count" 3
        (List.length (Command_result.artifacts result)))

let test_workspace_scan_chunked_identity () =
  with_temp_workspace (fun root ->
      let content =
        String.init ((65536 * 2) + 17) (fun index -> Char.chr (index mod 251))
      in
      write_file (Filename.concat root "large.bin") content;
      let result = Workspace_scan.scan ~workspace:root in
      Alcotest.(check string) "status" "ok" (result_status result);
      match Command_result.artifacts result with
      | [ artifact ] ->
          Alcotest.(check bool) "identity crosses multiple read chunks" true
            (Content_identity.equal (Artifact.content_identity artifact)
               (Content_identity.of_content content))
      | _ -> Alcotest.fail "expected exactly one artifact")

let test_workspace_scan_invalid_roots () =
  with_temp_workspace (fun root ->
      let missing = Workspace_scan.scan ~workspace:(Filename.concat root "missing") in
      Alcotest.(check string) "missing root status" "invalid-input"
        (result_status missing);
      Alcotest.(check string) "missing root exitClass" "usage-error"
        (result_exit_class missing);
      let file = Filename.concat root "file.txt" in
      write_file file "content";
      let not_directory = Workspace_scan.scan ~workspace:file in
      Alcotest.(check string) "file root status" "invalid-input"
        (result_status not_directory);
      Alcotest.(check string) "file root exitClass" "usage-error"
        (result_exit_class not_directory))

let test_workspace_scan_symlink_diagnostic () =
  if not Sys.win32 then
    with_temp_workspace (fun root ->
        write_file (Filename.concat root "target.txt") "target";
        Unix.symlink "target.txt" (Filename.concat root "link.txt");
        let result = Workspace_scan.scan ~workspace:root in
        Alcotest.(check string) "status" "diagnostics-found"
          (result_status result);
        Alcotest.(check string) "warning does not fail exit class" "success"
          (result_exit_class result);
        Alcotest.(check (list string)) "regular files only"
          [ "target.txt" ] (artifact_paths result);
        Alcotest.(check int) "one diagnostic" 1
          (List.length (Command_result.diagnostics result));
        match Command_result.diagnostics result with
        | [ diagnostic ] ->
            Alcotest.(check string) "filesystem-specific diagnostic code"
              "unsupported-filesystem-entry"
              (Diagnostic.code diagnostic |> Diagnostic.code_string)
        | _ -> Alcotest.fail "expected exactly one diagnostic")

let test_workspace_scan_root_symlink () =
  if not Sys.win32 then
    with_temp_workspace (fun root ->
        let actual = Filename.concat root "actual" in
        Unix.mkdir actual 0o700;
        write_file (Filename.concat actual "file.txt") "content";
        let link = Filename.concat root "workspace-link" in
        Unix.symlink "actual" link;
        let result = Workspace_scan.scan ~workspace:link in
        Alcotest.(check string) "status" "ok" (result_status result);
        Alcotest.(check string) "exitClass" "success"
          (result_exit_class result);
        Alcotest.(check (list string)) "root symlink is resolved once"
          [ "file.txt" ] (artifact_paths result))

let test_workspace_scan_special_entry_diagnostic () =
  if not Sys.win32 then
    with_temp_workspace (fun root ->
        Unix.mkfifo (Filename.concat root "events.fifo") 0o600;
        let result = Workspace_scan.scan ~workspace:root in
        Alcotest.(check string) "status" "diagnostics-found"
          (result_status result);
        Alcotest.(check (list string)) "special entry is not an artifact" []
          (artifact_paths result);
        match Command_result.diagnostics result with
        | [ diagnostic ] ->
            Alcotest.(check string) "filesystem-specific diagnostic code"
              "unsupported-filesystem-entry"
              (Diagnostic.code diagnostic |> Diagnostic.code_string)
        | _ -> Alcotest.fail "expected exactly one diagnostic")

let test_workspace_scan_io_failures_are_results () =
  if not Sys.win32 && Unix.geteuid () <> 0 then (
    with_temp_workspace (fun root ->
        let file = Filename.concat root "unreadable.txt" in
        write_file file "content";
        Fun.protect
          ~finally:(fun () -> Unix.chmod file 0o600)
          (fun () ->
            Unix.chmod file 0o000;
            let result = Workspace_scan.scan ~workspace:root in
            Alcotest.(check string) "unreadable file status" "internal-error"
              (result_status result);
            Alcotest.(check string) "unreadable file exitClass" "internal-error"
              (result_exit_class result)));
    with_temp_workspace (fun root ->
        let directory = Filename.concat root "unreadable" in
        Unix.mkdir directory 0o700;
        Fun.protect
          ~finally:(fun () -> Unix.chmod directory 0o700)
          (fun () ->
            Unix.chmod directory 0o000;
            let result = Workspace_scan.scan ~workspace:root in
            Alcotest.(check string) "unreadable directory status"
              "internal-error" (result_status result);
            Alcotest.(check string) "unreadable directory exitClass"
              "internal-error" (result_exit_class result))))

let () =
  Alcotest.run "monika_sugar semantic model"
    [
      ( "construction",
        [
          Alcotest.test_case "identifier" `Quick test_identifier;
          Alcotest.test_case "scoped identifiers and region address" `Quick
            test_scoped_identifiers_and_region_address;
          Alcotest.test_case "range" `Quick test_range;
          Alcotest.test_case "patch" `Quick test_patch;
          Alcotest.test_case "artifact origin and reference target" `Quick
            test_artifact_origin_and_reference_target;
          Alcotest.test_case "selector and expectation" `Quick
            test_selector_and_expectation;
          Alcotest.test_case "diagnostic severity" `Quick
            test_diagnostic_severity;
          Alcotest.test_case "command result" `Quick test_command_result;
          Alcotest.test_case "capability" `Quick test_capability;
          Alcotest.test_case "extension descriptor" `Quick
            test_extension_descriptor;
          Alcotest.test_case "normal command result" `Quick
            test_normal_command_result;
          Alcotest.test_case "proposed patch decoder" `Quick
            test_proposed_patch_decoder;
          Alcotest.test_case "validated conflicts" `Quick
            test_conflict_construction;
        ] );
      ( "workspace path",
        [
          Alcotest.test_case "POSIX" `Quick test_posix_paths;
          Alcotest.test_case "Windows" `Quick test_windows_paths;
          QCheck_alcotest.to_alcotest path_round_trip;
        ] );
      ( "content identity",
        [
          Alcotest.test_case "SHA-256" `Quick test_content_identity;
          Alcotest.test_case "protocol integer domain" `Quick
            test_protocol_integer_domain;
          Alcotest.test_case "schema-visible UTF-8" `Quick
            test_schema_visible_utf8;
        ] );
      ( "workspace operations",
        [
          Alcotest.test_case "snapshot normalization" `Quick
            test_workspace_snapshot;
          Alcotest.test_case "create patches" `Quick
            test_workspace_create_patch;
          Alcotest.test_case "text edits" `Quick test_text_edit_application;
          Alcotest.test_case "conflicts" `Quick test_workspace_conflicts;
          Alcotest.test_case "patch reapplication" `Quick
            test_patch_reapplication;
        ] );
      ( "filesystem apply",
        [
          Alcotest.test_case "create and reapply" `Quick
            test_filesystem_apply_create;
          Alcotest.test_case "commit fault states" `Quick
            test_filesystem_commit_faults;
          Alcotest.test_case "handle-relative containment" `Quick
            test_handle_boundary_holds_parent_descriptor;
          Alcotest.test_case "write and dry-run" `Quick
            test_filesystem_apply_write_and_dry_run;
          Alcotest.test_case "conflicts do not write" `Quick
            test_filesystem_apply_conflicts_do_not_write;
          Alcotest.test_case "preserves POSIX mode" `Quick
            test_filesystem_apply_preserves_posix_mode;
          Alcotest.test_case "safety" `Quick test_filesystem_apply_safety;
          Alcotest.test_case "native spelling" `Quick
            test_filesystem_apply_native_spelling;
          Alcotest.test_case "Windows reparse-point boundary" `Quick
            test_windows_reparse_point_boundary;
        ] );
      ( "workspace scan",
        [
          Alcotest.test_case "mutation retry is bounded" `Quick
            test_stable_read_mutation_retry;
          Alcotest.test_case "regular files" `Quick
            test_workspace_scan_regular_files;
          Alcotest.test_case "chunked content identity" `Quick
            test_workspace_scan_chunked_identity;
          Alcotest.test_case "invalid roots" `Quick
            test_workspace_scan_invalid_roots;
          Alcotest.test_case "symlink diagnostic" `Quick
            test_workspace_scan_symlink_diagnostic;
          Alcotest.test_case "root symlink" `Quick
            test_workspace_scan_root_symlink;
          Alcotest.test_case "special entry diagnostic" `Quick
            test_workspace_scan_special_entry_diagnostic;
          Alcotest.test_case "I/O failures are command results" `Quick
            test_workspace_scan_io_failures_are_results;
        ] );
      ( "inspect inputs",
        [
          Alcotest.test_case "retained-handle workspace read" `Quick
            test_workspace_read_regular_file;
          Alcotest.test_case "workspace read rejects symlinks" `Quick
            test_workspace_read_rejects_symlink;
          Alcotest.test_case "strict sidecar v1" `Quick
            test_sidecar_v1_strict_decode;
          Alcotest.test_case "sidecar edit location" `Quick
            test_sidecar_annotation_insertion_offset;
          Alcotest.test_case "authored overrides derived" `Quick
            test_sidecar_authored_overrides_derived;
          Alcotest.test_case "sidecar layout profile" `Quick
            test_sidecar_layout_profile;
          Alcotest.test_case "rejects ambiguous YAML" `Quick
            test_sidecar_v1_rejects_yaml_ambiguity;
          Alcotest.test_case "authored inspection priority" `Quick
            test_workspace_inspect_authored_priority;
          Alcotest.test_case "derive create/apply/idempotency" `Quick
            test_workspace_derive_create_apply_idempotent;
          Alcotest.test_case "derive preserves authored bytes" `Quick
            test_workspace_derive_preserves_authored_bytes;
          Alcotest.test_case "CommonMark observations" `Quick
            test_markdown_inspect_commonmark;
          Alcotest.test_case "CommonMark reference occurrences" `Quick
            test_markdown_reference_occurrences;
          Alcotest.test_case "annotation relation projection" `Quick
            test_relation_projection_from_annotation;
          Alcotest.test_case "workspace related query" `Quick
            test_workspace_graph_related_query;
          Alcotest.test_case "rejects invalid directives" `Quick
            test_markdown_inspect_rejects_invalid_directives;
          Alcotest.test_case "JSONL row-filter" `Quick test_jsonl_row_filter;
          Alcotest.test_case "JSONL failures" `Quick
            test_jsonl_row_filter_failures;
          Alcotest.test_case "resolve observation time" `Quick
            test_resolve_observation_time;
        ] );
    ]
