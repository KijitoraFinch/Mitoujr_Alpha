open Monika_sugar

let expect_ok = function
  | Ok value -> value
  | Error message -> Alcotest.fail message

let check_error = function
  | Ok _ -> Alcotest.fail "expected construction to fail"
  | Error _ -> ()

let test_identifier () =
  check_error (Identifier.make "");
  let value = expect_ok (Identifier.make "observation:readme") in
  Alcotest.(check string) "preserves value" "observation:readme"
    (Identifier.to_string value)

let test_region_extent_relation () =
  let path = expect_ok (Workspace_path.of_segments [ "regions.bin" ]) in
  let observation_id = expect_ok (Observation_id.make "observation:regions.bin") in
  let observation =
    Observation.of_bytes ~id:observation_id
      ~origin:(Observation.workspace path) ~observation_type:Observation_type.binary
      ~bytes:(String.make 20 'x')
  in
  let interpreter =
    expect_ok (Interpreter.make ~name:"test-ranges" ~version:"1" ())
  in
  let region local start end_ =
    let id = expect_ok (Region_id.make ~observation:observation_id ~local) in
    let selector =
      Selector.Region_id (expect_ok (Identifier.make ("selector:" ^ local)))
    in
    let range = expect_ok (Text_range.make ~start ~end_) in
    expect_ok
      (Region.make ~id ~observation_identity:(Observation.identity observation)
         ~selector ~interpreter ~range ())
  in
  let whole_id =
    expect_ok (Region_id.make ~observation:observation_id ~local:"whole")
  in
  let whole =
    Region.whole ~id:whole_id
      ~observation_identity:(Observation.identity observation)
  in
  let outer = region "outer" 2 12 in
  let middle = region "middle" 3 10 in
  let inner = region "inner" 4 8 in
  let same_extent = region "same-extent-different-selector" 2 12 in
  let overlap = region "overlap" 7 15 in
  let separate = region "separate" 15 20 in
  let check expected left right =
    Alcotest.(check string) "extent relation"
      (Region_extent_relation.to_string expected)
      (Region_extent_relation.classify_builtin left right |> expect_ok
      |> Region_extent_relation.to_string)
  in
  check Region_extent_relation.Equal outer outer;
  check Region_extent_relation.Equal outer same_extent;
  check Region_extent_relation.Contains outer inner;
  check Region_extent_relation.Contains outer middle;
  check Region_extent_relation.Contains middle inner;
  check Region_extent_relation.Contained_by inner outer;
  check Region_extent_relation.Overlaps outer overlap;
  check Region_extent_relation.Disjoint inner separate;
  check Region_extent_relation.Contains whole outer;
  check Region_extent_relation.Contained_by outer whole;
  let other_observation_id =
    expect_ok (Observation_id.make "observation:copy-of-regions.bin")
  in
  let other_region_id =
    expect_ok
      (Region_id.make ~observation:other_observation_id ~local:"outer")
  in
  let other_region =
    expect_ok
      (Region.make ~id:other_region_id
         ~observation_identity:(Observation.identity observation)
         ~selector:
           (Selector.Region_id (expect_ok (Identifier.make "selector:outer")))
         ~interpreter ~range:(expect_ok (Text_range.make ~start:2 ~end_:12))
         ())
  in
  check_error (Region_extent_relation.classify_builtin outer other_region);
  List.iter
    (fun (left, right) ->
      let forward =
        Region_extent_relation.classify_builtin left right |> expect_ok
      in
      let reverse =
        Region_extent_relation.classify_builtin right left |> expect_ok
      in
      Alcotest.(check string) "swapping arguments inverts the relation"
        (forward |> Region_extent_relation.invert
        |> Region_extent_relation.to_string)
        (Region_extent_relation.to_string reverse))
    [
      (outer, same_extent);
      (outer, inner);
      (inner, outer);
      (outer, overlap);
      (inner, separate);
    ];
  List.iter
    (fun relation ->
      Alcotest.(check string) "inversion is involutive"
        (Region_extent_relation.to_string relation)
        (relation |> Region_extent_relation.invert
        |> Region_extent_relation.invert
        |> Region_extent_relation.to_string))
    [
      Region_extent_relation.Equal;
      Region_extent_relation.Contains;
      Region_extent_relation.Contained_by;
      Region_extent_relation.Overlaps;
      Region_extent_relation.Disjoint;
    ];
  (match
     Extension_protocol.decode_classify_result
       (`Assoc [ ("relation", `String "contains") ])
   with
  | Ok (Extension_protocol.Classified relation) ->
      Alcotest.(check string) "protocol relation" "contains"
        (Region_extent_relation.to_string relation)
  | Ok (Extension_protocol.Classify_failure _)
  | Error _ -> Alcotest.fail "expected a classified protocol result");
  check_error
    (Extension_protocol.decode_classify_result
       (`Assoc [ ("relation", `String "touches") ]))

let test_registry_snapshot () =
  let manifest =
    Extension_manifest.of_yojson
      (`Assoc
        [
          ("protocolVersion", `String "1");
          ( "capability",
            `Assoc
              [
                ("type", `String "interpreter");
                ("name", `String "registry-test");
                ("version", `String "1");
                ("acceptedObservationTypes", `List []);
                ("applicability", `Assoc [ ("pathGlobs", `List []) ]);
                ("selectorSchemas", `List []);
                ( "resultSchemas",
                  `List
                    [
                      `String
                        "https://monika.local/schemas/interpretation.schema.json";
                    ] );
              ] );
        ])
    |> expect_ok
  in
  check_error
    (Installed_extension.make ~manifest ~executable:"relative-command"
       ~arguments:[]);
  let installed =
    Installed_extension.make ~manifest ~executable:"/usr/bin/env"
      ~arguments:[ "python3" ]
    |> expect_ok
  in
  check_error (Registry_snapshot.make [ installed; installed ]);
  let snapshot = Registry_snapshot.make [ installed ] |> expect_ok in
  let interpreter =
    expect_ok (Interpreter.make ~name:"registry-test" ~version:"1" ())
  in
  Alcotest.(check bool) "exact interpreter lookup" true
    (Registry_snapshot.find_interpreter snapshot interpreter |> Option.is_some);
  let built_in_collision_manifest =
    Extension_manifest.of_yojson
      (`Assoc
        [
          ("protocolVersion", `String "1");
          ( "capability",
            `Assoc
              [
                ("type", `String "interpreter");
                ("name", `String "markdown");
                ("version", `String "1");
                ("acceptedObservationTypes", `List []);
                ("applicability", `Assoc [ ("pathGlobs", `List []) ]);
                ("selectorSchemas", `List []);
                ( "resultSchemas",
                  `List
                    [
                      `String
                        "https://monika.local/schemas/interpretation.schema.json";
                    ] );
              ] );
        ])
    |> expect_ok
  in
  let collision =
    Installed_extension.make ~manifest:built_in_collision_manifest
      ~executable:"/usr/bin/env" ~arguments:[]
    |> expect_ok |> fun extension -> Registry_snapshot.make [ extension ]
    |> expect_ok
  in
  let markdown =
    expect_ok (Interpreter.make ~name:"markdown" ~version:"1" ())
  in
  check_error (Interpreter_dispatcher.find_exact collision markdown);
  let markdown_selected =
    match
      Interpreter_dispatcher.find_exact Registry_snapshot.empty markdown
      |> expect_ok
    with
    | Some selected -> selected
    | None -> Alcotest.fail "built-in Markdown Interpreter was not found"
  in
  let observation path observation_type content =
    let path = expect_ok (Workspace_path.of_canonical_string path) in
    let id =
      expect_ok
        (Observation_id.make
           ("observation:" ^ Workspace_path.to_canonical_string path))
    in
    Observation.of_bytes ~id ~origin:(Observation.workspace path)
      ~observation_type ~bytes:content
  in
  let markdown_observation =
    observation "docs/example.md" Observation_type.markdown "# Example\n"
  in
  let jsonl_type =
    expect_ok
      (Observation_type.make ~name:"application/x-ndjson" ~version:"1" ())
  in
  let jsonl_observation = observation "data/example.jsonl" jsonl_type "{}\n" in
  Alcotest.(check bool) "exact built-in accepts its ObservationType" true
    (Interpreter_dispatcher.accepts markdown_selected markdown_observation
    |> expect_ok);
  Alcotest.(check bool)
    "exact built-in rejects a different fixed ObservationType" false
    (Interpreter_dispatcher.accepts markdown_selected jsonl_observation
    |> expect_ok);
  check_error
    (Registry_snapshot.of_yojson
       (`Assoc
         [
           ("schemaVersion", `String "1");
           ("extensions", `List []);
           ("extensions", `List []);
         ]))

let test_resource_observation_abstractions () =
  let resource_observer =
    expect_ok
      (Resource_observer.make ~name:"github.issue" ~version:"1" ())
  in
  let origin =
    expect_ok
      (Origin.extension ~observer:resource_observer
         ~locator:
           (`Assoc
             [
               ("owner", `String "octo");
               ("repo", `String "example");
               ("number", `Int 42);
             ])
         ())
  in
  let issue_type =
    expect_ok (Observation_type.make ~name:"github.issue" ~version:"1" ())
  in
  let issue_identity =
    expect_ok
      (Observation_identity.make ~observation_type:issue_type
         ~key:"node:MDU6SXNzdWU0Mg==:updated:2026-08-06T10:00:00Z" ())
  in
  let observation_id =
    expect_ok (Observation_id.make "observation:github-issue-42")
  in
  let observation =
    expect_ok
      (Observation.of_structured ~id:observation_id ~origin
         ~identity:issue_identity ~schema:"github.issue/v1"
         ~value:(`Assoc [ ("title", `String "Example") ]) ())
  in
  Alcotest.(check string) "extension observer" "github.issue"
    (match Observation.origin observation with
    | Origin.Extension value -> Resource_observer.name value.observer
    | _ -> Alcotest.fail "expected an extension origin");
  Alcotest.(check string) "observation type" "github.issue"
    (Observation.observation_type observation |> Observation_type.name);
  Alcotest.(check bool) "observation is self-identical" true
    (Observation.same observation observation);
  (match Observation.representation observation with
  | Observation.Structured structured ->
      Alcotest.(check string) "structured schema" "github.issue/v1"
        structured.schema;
      Alcotest.(check string) "structured value is host-owned and canonical"
        {|{"title":"Example"}|}
        (Normalized_value.canonical_json structured.value)
  | Observation.Bytes _ ->
      Alcotest.fail "expected a structured observation representation");
  Alcotest.(check (option string)) "structured observations are not byte-backed"
    None (Observation.bytes observation);
  let next_identity =
    expect_ok
      (Observation_identity.make ~observation_type:issue_type
         ~key:"node:MDU6SXNzdWU0Mg==:updated:2026-08-06T10:01:00Z" ())
  in
  Alcotest.(check bool) "same resource can produce a new observation" false
    (Observation_identity.equal issue_identity next_identity);
  let source_type =
    expect_ok
      (Observation_type.make ~name:"language.rust.source" ~version:"1" ())
  in
  let same_key_other_type =
    expect_ok
      (Observation_identity.make ~observation_type:source_type
         ~key:
           "node:MDU6SXNzdWU0Mg==:updated:2026-08-06T10:00:00Z"
         ())
  in
  Alcotest.(check bool) "type participates in observation identity" false
    (Observation_identity.equal issue_identity same_key_other_type);
  let rust_v1 =
    expect_ok (Interpreter.make ~name:"rust.item" ~version:"1" ())
  in
  let rust_v2 =
    expect_ok (Interpreter.make ~name:"rust.item" ~version:"2" ())
  in
  let selector =
    expect_ok
      (Selector.extension ~schema:"rust.item-selector/v1"
         ~value:
           (`Assoc
             [ ("name", `String "Request"); ("kind", `String "struct") ]))
  in
  let reordered_selector =
    expect_ok
      (Selector.extension ~schema:"rust.item-selector/v1"
         ~value:
           (`Assoc
             [ ("kind", `String "struct"); ("name", `String "Request") ]))
  in
  Alcotest.(check bool) "extension selector object order is canonical" true
    (Selector.compare selector reordered_selector = 0);
  check_error (Selector.extension ~schema:"" ~value:`Null);
  check_error
    (Selector.extension ~schema:"example/v1"
       ~value:(`Assoc [ ("duplicate", `Null); ("duplicate", `Bool true) ]));
  check_error (Selector.extension ~schema:"example/v1" ~value:(`Float 0.5));
  let v1_resolution =
    Region_resolution.make ~interpreter:rust_v1
      ~observation_identity:same_key_other_type ~selector
  in
  let v2_resolution =
    Region_resolution.make ~interpreter:rust_v2
      ~observation_identity:same_key_other_type ~selector
  in
  Alcotest.(check bool) "interpreter version participates in resolution" false
    (Region_resolution.equal v1_resolution v2_resolution);
  let observation =
    expect_ok
      (Observation.make ~id:observation_id ~origin ~identity:issue_identity
         ~representation:(Observation.Bytes "canonical issue value") ())
  in
  let region_id =
    expect_ok (Region_id.make ~observation:observation_id ~local:"selected-part")
  in
  let issue_interpreter =
    expect_ok
      (Interpreter.make ~name:"github.issue.part" ~version:"1" ())
  in
  let issue_selector =
    expect_ok
      (Selector.extension ~schema:"github.issue-part-selector/v1"
         ~value:
           (`Assoc
             [ ("kind", `String "comment"); ("databaseId", `Int 314) ]))
  in
  let region =
    expect_ok
      (Region.make ~id:region_id
         ~observation_identity:(Observation.identity observation)
         ~selector:issue_selector ~interpreter:issue_interpreter ())
  in
  let result =
    expect_ok
      (Command_result.make ~command:"inspect"
         ~termination:Command_result.Completed ~effect:Command_result.No_change
         ~observations:[ observation ] ~regions:[ region ] ())
    |> Normal.Command_result.normalize |> Normal_json.command_result
  in
  let open Yojson.Safe.Util in
  Alcotest.(check string) "extension origin reaches the normal form" "extension"
    (result |> member "observations" |> index 0 |> member "origin" |> member "kind"
   |> to_string);
  Alcotest.(check string) "resource observer reaches the normal form"
    "github.issue"
    (result |> member "observations" |> index 0 |> member "origin"
   |> member "observer" |> member "name" |> to_string);
  Alcotest.(check string) "resource observer version reaches the normal form"
    "1"
    (result |> member "observations" |> index 0 |> member "origin"
   |> member "observer" |> member "version" |> to_string);
  Alcotest.(check string) "representation reaches the normal form" "bytes"
    (result |> member "observations" |> index 0 |> member "representation"
   |> member "kind" |> to_string);
  Alcotest.(check string) "extension selector reaches the normal form"
    "github.issue-part-selector/v1"
    (result |> member "regions" |> index 0 |> member "selector"
   |> member "schema" |> to_string);
  check_error (Resource_observer.make ~name:"" ~version:"1" ());
  check_error
    (Origin.extension ~observer:resource_observer
       ~locator:(`Assoc [ ("duplicate", `Null); ("duplicate", `Null) ]) ());
  check_error
    (Observation_type.make ~name:"github.issue" ~version:"" ());
  check_error
    (Observation_identity.make ~observation_type:issue_type ~key:"" ())

let test_scoped_identifiers_and_region_address () =
  let left_observation = expect_ok (Observation_id.make "observation:left") in
  let right_observation = expect_ok (Observation_id.make "observation:right") in
  let left =
    expect_ok (Region_id.make ~observation:left_observation ~local:"heading")
  in
  let same =
    expect_ok (Region_id.make ~observation:left_observation ~local:"heading")
  in
  let other_scope =
    expect_ok (Region_id.make ~observation:right_observation ~local:"heading")
  in
  Alcotest.(check bool) "same scoped ID" true (Region_id.equal left same);
  Alcotest.(check bool) "observation participates in identity" false
    (Region_id.equal left other_scope);
  let left_scope = expect_ok (Observation.generated "left") in
  let right_scope = expect_ok (Observation.generated "right") in
  check_error (Reference_id.make ~scope:left_scope ~local:"");
  let target_path = expect_ok (Workspace_path.of_segments [ "docs"; "note.md" ]) in
  let address =
    expect_ok
      (Region_address.make ~origin:(Observation.workspace target_path)
         ~selector:Selector.Whole_observation ())
  in
  Alcotest.(check string) "unresolved address retains observation" "docs/note.md"
    (match Region_address.origin address with
    | Origin.Workspace path -> Workspace_path.to_canonical_string path
    | _ -> Alcotest.fail "expected workspace address");
  let annotation =
    expect_ok (Annotation_id.make ~scope:right_scope ~local:"annotation")
  in
  Alcotest.(check bool) "annotation scope is independent from observations" true
    (Origin.equal right_scope (Annotation_id.scope annotation));
  let observation =
    Observation.of_bytes ~id:left_observation
      ~origin:(Observation.workspace target_path)
      ~observation_type:Observation_type.binary
      ~bytes:""
  in
  let region =
    Region.whole ~id:left
      ~observation_identity:(Observation.identity observation)
  in
  Alcotest.(check (option string)) "whole region needs no interpreter" None
    (Region.interpreter region);
  check_error
    (Command_result.make ~command:"inspect"
       ~termination:Command_result.Completed ~effect:Command_result.No_change
       ~observations:[ observation ] ~regions:[ region; region ] ());
  check_error
    (Command_result.make ~command:"inspect"
       ~termination:Command_result.Completed ~effect:Command_result.No_change
       ~regions:[ region ] ())
  ;
  let other_identity =
    expect_ok
      (Observation_identity.make
         ~observation_type:
           (Observation.observation_type observation)
         ~key:"a different observation" ())
  in
  let mismatched = Region.whole ~id:left ~observation_identity:other_identity in
  check_error
    (Command_result.make ~command:"inspect"
       ~termination:Command_result.Completed ~effect:Command_result.No_change
       ~observations:[ observation ] ~regions:[ mismatched ] ())

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
    |> expect_ok |> fun state ->
    Content_digest.Incremental.feed_bytes state buffer ~offset:7 ~length:4
    |> expect_ok |> Content_digest.Incremental.finish
  in
  check_error
    (Content_digest.Incremental.feed_bytes
       (Content_digest.Incremental.empty ()) buffer ~offset:(-1) ~length:1);
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

let test_observation_origin_and_reference_target () =
  let path =
    expect_ok
      (Workspace_path.of_native_string ~flavor:Workspace_path.Posix
         "runs/metrics.jsonl")
  in
  let workspace = Observation.workspace path in
  let observation_id = expect_ok (Observation_id.make "observation:metrics") in
  let content_identity = Content_identity.of_content "{}\n" in
  check_error (Observation_type.make ~name:"" ~version:"1" ());
  let observation_type =
    expect_ok
      (Observation_type.make ~name:"application/jsonl" ~version:"1" ())
  in
  let observation =
    Observation.of_bytes ~id:observation_id ~origin:workspace
      ~observation_type ~bytes:"{}\n"
  in
  Alcotest.(check string) "observation exposes its observation type"
    "application/jsonl"
    (Observation.observation_type observation |> Observation_type.name);
  Alcotest.(check bool) "observation identity belongs to its observation type" true
    (Observation_type.equal
       (Observation.identity observation
       |> Observation_identity.observation_type)
       (Observation.observation_type observation));
  Alcotest.(check bool) "content identity is explicit adapter data" true
    (Option.equal Content_identity.equal (Some content_identity)
       (Observation.content_identity observation));
  check_error (Observation.git ~repo:"" ~path:"file.txt" ());
  check_error (Observation.git ~repo:"repo" ~rev:"" ~path:"file.txt" ());
  check_error (Observation.git ~repo:"repo" ~path:"" ());
  check_error (Observation.web "");
  check_error (Observation.generated "");
  check_error (Observation.external_ "");
  let git = expect_ok (Observation.git ~repo:"repo" ~path:"file.txt" ()) in
  (match git with
  | Origin.Git value ->
      Alcotest.(check string) "repo" "repo" value.repo
  | _ -> Alcotest.fail "expected git origin");
  check_error
    (Reference.make_target ~origin:workspace
       ~selector:Selector.Whole_observation ~interpreter:"" ());
  let whole_target =
    expect_ok
      (Reference.make_target ~origin:workspace
         ~selector:Selector.Whole_observation ())
  in
  Alcotest.(check bool) "whole-observation selector is explicit" true
    (Selector.compare (Reference.target_selector whole_target)
       Selector.Whole_observation
    = 0);
  let selected_region =
    Selector.Region_id (expect_ok (Identifier.make "selected-row"))
  in
  check_error
    (Reference.make_target ~origin:workspace ~selector:selected_region
       ~interpreter:"jsonl" ());
  let target =
    expect_ok
      (Reference.make_target ~origin:workspace
         ~selector:selected_region ~interpreter:"jsonl"
         ~interpreter_version:"1" ())
  in
  Alcotest.(check (option string)) "interpreter" (Some "jsonl")
    (Reference.target_interpreter target);
  Alcotest.(check (option string)) "explicit interpreter version" (Some "1")
    (Reference.target_interpreter_version target);
  let target_v2 =
    expect_ok
      (Reference.make_target ~origin:workspace
         ~selector:selected_region ~interpreter:"jsonl"
         ~interpreter_version:"2" ())
  in
  Alcotest.(check bool) "address comparison includes interpreter version" false
    (Reference.compare_target target target_v2 = 0);
  Alcotest.(check bool) "selected region is retained" true
    (Selector.compare (Reference.target_selector target) selected_region = 0)

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
  let source_scope = expect_ok (Observation.generated "metrics") in
  let id =
    expect_ok (Reference_id.make ~scope:source_scope ~local:"latency-run-a")
  in
  let observation_path =
    expect_ok
      (Workspace_path.of_native_string ~flavor:Workspace_path.Posix
         "runs/metrics.jsonl")
  in
  let target =
    expect_ok
      (Reference.make_target ~origin:(Observation.workspace observation_path)
         ~selector:(Selector.Row_filter filter) ~interpreter:"jsonl"
         ~interpreter_version:"1" ())
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
      (Diagnostic.Unsupported_observation, "warning");
      (Diagnostic.Unsupported_filesystem_entry, "warning");
      (Diagnostic.Observation_failure, "error");
      (Diagnostic.Metadata_failure, "error");
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
           Diagnostic.observation = None;
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
  Alcotest.(check string) "resource observer kind" "resource-observer"
    (Capability.kind_string Capability.Resource_observer);
  check_error
    (Capability.make ~kind:Capability.Interpreter ~name:"" ~version:"1" ());
  check_error
    (Capability.make ~kind:Capability.Interpreter ~name:"markdown"
       ~version:"1"
       ~applies_to:
         Capability.{
           observation_types =
             [ Observation_type.markdown; Observation_type.markdown ];
           path_globs = [];
         }
       ());
  check_error
    (Capability.make ~kind:Capability.Interpreter ~name:"markdown"
       ~version:"1"
       ~schemas:
         Capability.{ selector_schemas = []; result_schemas = [] }
       ());
  let capability =
    expect_ok
      (Capability.make ~kind:Capability.Interpreter ~name:"markdown"
         ~version:"1"
         ~applies_to:
           Capability.{
             observation_types = [ Observation_type.markdown ];
             path_globs = [];
           }
         ())
  in
  check_error
    (Command_result.make ~command:"capabilities"
       ~termination:Command_result.Completed ~effect:Command_result.No_change
       ~capabilities:[ capability; capability ] ())

let test_extension_applicability () =
  let path value =
    expect_ok (Workspace_path.of_canonical_string value)
  in
  let glob value = expect_ok (Path_glob.make value) in
  Alcotest.(check bool) "single star matches one segment" true
    (Path_glob.matches (glob "docs/*.md") (path "docs/note.md"));
  Alcotest.(check bool) "single star does not cross a separator" false
    (Path_glob.matches (glob "docs/*.md") (path "docs/nested/note.md"));
  Alcotest.(check bool) "globstar matches no leading segment" true
    (Path_glob.matches (glob "**/*.example") (path "input.example"));
  Alcotest.(check bool) "globstar matches leading segments" true
    (Path_glob.matches (glob "**/*.example")
       (path "fixtures/input.example"));
  check_error (Path_glob.make "/docs/*.md");
  check_error (Path_glob.make "docs//*.md");
  check_error (Path_glob.make "docs/***.md");
  check_error (Path_glob.make "docs/?.md");
  let capability observation_type_names path_globs =
    let observation_types =
      List.map
        (fun name ->
          expect_ok (Observation_type.make ~name ~version:"1" ()))
        observation_type_names
    in
    expect_ok
      (Capability.make ~kind:Capability.Interpreter ~name:"example"
         ~version:"1"
         ~applies_to:Capability.{ observation_types; path_globs } ())
  in
  let associated_observation_type capability path =
    match Extension_applicability.associate capability ~path with
    | Ok (Extension_applicability.Associated observation_type) ->
        Some (Observation_type.name observation_type)
    | Ok Extension_applicability.Not_associated -> None
    | Error message -> Alcotest.fail message
  in
  Alcotest.(check (option string)) "known ObservationType is matched"
    (Some "text/markdown")
    (associated_observation_type
       (capability [ "text/markdown" ] [])
       (path "docs/note.md"));
  Alcotest.(check (option string)) "known ObservationType mismatch is explicit" None
    (associated_observation_type
       (capability [ "application/x-ndjson" ] [])
       (path "docs/note.md"));
  Alcotest.(check (option string)) "glob assigns one declared ObservationType"
    (Some "text/x-example")
    (associated_observation_type
       (capability [ "text/x-example" ] [ "**/*.example" ])
       (path "fixtures/input.example"));
  Alcotest.(check (option string)) "path mismatch is not applicable" None
    (associated_observation_type
       (capability [ "text/x-example" ] [ "src/*.example" ])
       (path "fixtures/input.example"));
  check_error
    (Extension_applicability.associate
       (capability [ "text/x-first"; "text/x-second" ] [ "**/*.example" ])
       ~path:(path "input.example"));
  let markdown_path = path "docs/note.md" in
  let markdown_observation =
    Observation.of_bytes
      ~id:(expect_ok (Observation_id.make "observation:docs/note.md"))
      ~origin:(Observation.workspace markdown_path)
      ~observation_type:
        (expect_ok
           (Observation_type.make ~name:"text/markdown" ~version:"1" ()))
      ~bytes:"# Note\n"
  in
  Alcotest.(check bool) "applicability consumes the fixed observation" true
    (expect_ok
       (Extension_applicability.accepts
          (capability [ "text/markdown" ] [])
          ~observation:markdown_observation));
  let binary_observation =
    Observation.of_bytes
      ~id:(Observation.id markdown_observation)
      ~origin:(Observation.origin markdown_observation)
      ~observation_type:Observation_type.binary
      ~bytes:"# Note\n"
  in
  Alcotest.(check bool) "interpreter cannot reclassify an observation" false
    (expect_ok
       (Extension_applicability.accepts
          (capability [ "text/markdown" ] [])
          ~observation:binary_observation));
  check_error
    (Capability.make ~kind:Capability.Interpreter ~name:"example"
       ~version:"1"
         ~applies_to:
         Capability.{
           observation_types =
             [
               expect_ok
                 (Observation_type.make ~name:"text/x-example" ~version:"1" ());
             ];
           path_globs = [ "docs/***.example" ];
         }
       ())

let test_extension_manifest () =
  let capability =
    `Assoc
      [
        ("type", `String "interpreter");
        ("name", `String "custom-markdown");
        ("version", `String "1");
        ( "acceptedObservationTypes",
          `List
            [
              `Assoc
                [
                  ("name", `String "text/markdown");
                  ("version", `String "1");
                ];
            ] );
        ( "applicability",
          `Assoc
            [
              ("pathGlobs", `List []);
            ] );
        ("selectorSchemas", `List []);
        ( "resultSchemas",
          `List
            [
              `String "https://monika.local/schemas/interpretation.schema.json";
            ] );
      ]
  in
  let manifest =
    expect_ok
      (Extension_manifest.of_yojson
         (`Assoc
           [ ("protocolVersion", `String "1"); ("capability", capability) ]))
  in
  Alcotest.(check string) "protocol version" "1"
    (Extension_manifest.protocol_version manifest);
  Alcotest.(check string) "capability name" "custom-markdown"
    (Extension_manifest.capability manifest |> Capability.name);
  List.iter
    (fun capability_type ->
      ignore
        (expect_ok
        (Extension_manifest.of_yojson
           (`Assoc
             [
               ("protocolVersion", `String "1");
               ( "capability",
                 `Assoc
                   [
                     ("type", `String capability_type);
                     ("name", `String "not-yet-executable");
                     ("version", `String "1");
                     ("acceptedObservationTypes", `List []);
                     ("applicability", `Assoc [ ("pathGlobs", `List []) ]);
                     ("selectorSchemas", `List []);
                     ( "resultSchemas",
                       `List
                         [
                           `String
                             "https://example.invalid/schemas/result.json";
                         ] );
                   ] );
             ]))))
    [
      "resource-observer";
      "annotation-extractor";
      "reference-extractor";
      "deriver";
      "auditor";
      "renderer";
      "indexer";
    ];
  List.iter
    (fun schema_name ->
      check_error
        (Extension_manifest.of_yojson
           (`Assoc
             [
               ("protocolVersion", `String "1");
               ( "capability",
                 `Assoc
                   [
                     ("type", `String "interpreter");
                     ("name", `String "unsupported-schema-declaration");
                     ("version", `String "1");
                     ( "schemas",
                       `Assoc
                         [
                           ( schema_name,
                             `String
                               "https://example.invalid/schemas/unused.json" );
                         ] );
                   ] );
             ])))
    [ "annotation"; "options" ];
  check_error
    (Extension_manifest.of_yojson
       (`Assoc
         [
           ("protocolVersion", `String "1");
           ("protocolVersion", `String "1");
           ("capability", capability);
         ]));
  check_error
    (Extension_manifest.of_yojson
       (`Assoc
         [ ("protocolVersion", `String "2"); ("capability", capability) ]));
  check_error
    (Extension_manifest.of_yojson
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
    (Extension_manifest.of_yojson
       (`Assoc
         [
           ("protocolVersion", `String "1");
           ( "capability",
             `Assoc
               [
                 ("type", `String "interpreter");
                 ("name", `String "invalid-glob");
                 ("version", `String "1");
                 ( "acceptedObservationTypes",
                   `List
                     [
                       `Assoc
                         [
                           ("name", `String "text/x-example");
                           ("version", `String "1");
                         ];
                     ] );
                 ( "applicability",
                   `Assoc
                     [
                       ("pathGlobs", `List [ `String "docs/***.example" ]);
                     ] );
                 ("selectorSchemas", `List []);
                 ( "resultSchemas",
                   `List
                     [
                       `String
                         "https://monika.local/schemas/interpretation.schema.json";
                     ] );
               ] );
         ]));
  check_error
    (Extension_manifest.of_yojson
       (`Assoc
         [
           ("protocolVersion", `String "1");
           ("capability", capability);
           ("bad\255field", `Bool true);
         ]))

let test_extension_resolve_result_validation () =
  let selector_schema =
    "https://example.invalid/schemas/custom-markdown-selector-v1.json"
  in
  let manifest =
    expect_ok
      (Extension_manifest.of_yojson
         (`Assoc
           [
             ("protocolVersion", `String "1");
             ( "capability",
               `Assoc
                 [
                   ("type", `String "interpreter");
                   ("name", `String "custom-markdown");
                   ("version", `String "1");
                   ("acceptedObservationTypes", `List []);
                   ("applicability", `Assoc [ ("pathGlobs", `List []) ]);
                   ("selectorSchemas", `List [ `String selector_schema ]);
                   ( "resultSchemas",
                     `List
                       [
                         `String
                           "https://monika.local/schemas/interpretation.schema.json";
                       ] );
                 ] );
           ]))
  in
  let target_path = expect_ok (Workspace_path.of_segments [ "target.md" ]) in
  let target_id = expect_ok (Observation_id.make "observation:target.md") in
  let target_observation =
    Observation.of_bytes ~id:target_id
      ~origin:(Observation.workspace target_path)
      ~observation_type:
        (expect_ok
           (Observation_type.make ~name:"text/markdown" ~version:"1" ()))
      ~bytes:"target"
  in
  let requested_selector =
    expect_ok
      (Selector.extension ~schema:selector_schema
         ~value:(`Assoc [ ("kind", `String "document") ]))
  in
  let selector_json value =
    `Assoc
      [
        ("kind", `String "extension");
        ("schema", `String selector_schema);
        ("value", `Assoc [ ("kind", `String value) ]);
      ]
  in
  let region ?(observation = "observation:target.md") ?(selector = "document")
      ?(range_end = 6) () =
    `Assoc
      [
        ( "id",
          `Assoc
            [
              ("observation", `String observation);
              ("local", `String "extension:document");
            ] );
        ("selector", selector_json selector);
        ("summary", `String "resolved target");
        ("range", `Assoc [ ("start", `Int 0); ("end", `Int range_end) ]);
      ]
  in
  let decode result =
    Extension_protocol.decode_resolve_result ~manifest
      ~target_observation
      ~requested_selector result
  in
  (match decode (`Assoc [ ("region", region ()) ]) |> expect_ok with
  | Extension_protocol.Resolved_region resolved ->
      Alcotest.(check bool) "requested selector is retained" true
        (Selector.compare requested_selector (Region.selector resolved) = 0);
      Alcotest.(check (option string)) "manifest interpreter is filled"
        (Some "custom-markdown") (Region.interpreter resolved)
  | Extension_protocol.Resolve_failure _ ->
      Alcotest.fail "expected a resolved extension region");
  check_error (decode (`Assoc [ ("region", region ~selector:"other" ()) ]));
  check_error
    (decode (`Assoc [ ("region", region ~observation:"observation:other.md" ()) ]));
  check_error (decode (`Assoc [ ("region", region ~range_end:7 ()) ]));
  match
    decode
      (`Assoc
        [
          ( "failure",
            `Assoc
              [
                ("code", `String "not-found");
                ("message", `String "target disappeared");
                ("data", `Assoc [ ("retryable", `Bool false) ]);
              ] );
        ])
    |> expect_ok
  with
  | Extension_protocol.Resolve_failure failure ->
      Alcotest.(check string) "failure code" "not-found"
        (Extension_failure.code failure);
      Alcotest.(check string) "failure message" "target disappeared"
        (Extension_failure.message failure);
      Alcotest.(check bool) "failure data retained" true
        (Option.is_some (Extension_failure.data failure))
  | Extension_protocol.Resolved_region _ ->
      Alcotest.fail "expected an extension resolution failure"

let test_extension_interpretation_result_validation () =
  let manifest =
    expect_ok
      (Extension_manifest.of_yojson
         (`Assoc
           [
             ("protocolVersion", `String "1");
             ( "capability",
               `Assoc
                 [
                   ("type", `String "interpreter");
                   ("name", `String "custom-markdown");
                   ("version", `String "1");
                   ( "acceptedObservationTypes",
                     `List
                       [
                         `Assoc
                           [
                             ("name", `String "text/markdown");
                             ("version", `String "1");
                           ];
                       ] );
                   ("applicability", `Assoc [ ("pathGlobs", `List []) ]);
                   ("selectorSchemas", `List []);
                   ( "resultSchemas",
                     `List
                       [
                         `String
                           "https://monika.local/schemas/interpretation.schema.json";
                       ] );
                 ] );
           ]))
  in
  let path = expect_ok (Workspace_path.of_segments [ "target.md" ]) in
  let id = expect_ok (Observation_id.make "observation:target.md") in
  let primary_observation =
    Observation.of_bytes ~id ~origin:(Observation.workspace path)
      ~observation_type:
        (expect_ok
           (Observation_type.make ~name:"text/markdown" ~version:"1" ()))
      ~bytes:"target"
  in
  let interpretation region_id range_end =
    `Assoc
      [
        ( "interpretation",
          `Assoc
            [
              ( "interpreter",
                `Assoc
                  [
                    ("name", `String "custom-markdown");
                    ("version", `String "1");
                  ] );
              ("observation", `String region_id);
              ( "regions",
                `List
                  [
                    `Assoc
                      [
                        ( "id",
                          `Assoc
                            [
                              ("observation", `String region_id);
                              ("local", `String "extension:document");
                            ] );
                        ( "selector",
                          `Assoc
                            [
                              ("kind", `String "text-range");
                              ( "range",
                                `Assoc
                                  [
                                    ("start", `Int 0);
                                    ("end", `Int range_end);
                                  ] );
                            ] );
                        ("range", `Assoc [ ("start", `Int 0); ("end", `Int range_end) ]);
                      ];
                  ] );
            ] );
      ]
  in
  let decode value =
    Extension_protocol.decode_interpret_result ~manifest
      ~primary_observation value
  in
  (match decode (interpretation "observation:target.md" 6) |> expect_ok with
  | Extension_protocol.Interpretation interpreted ->
      Alcotest.(check int) "interpreted regions" 1
        (List.length (Interpretation.regions interpreted))
  | Extension_protocol.Interpret_failure _ ->
      Alcotest.fail "expected an interpretation");
  check_error (decode (interpretation "observation:missing.md" 6));
  check_error (decode (interpretation "observation:target.md" 7));
  check_error
    (decode
       (`Assoc
         [
           ( "interpretation",
             `Assoc
               [
                 ("observations", `List []);
                 ("regions", `List []);
               ] );
         ]));
  check_error
    (decode
       (`Assoc
         [
           ( "observation",
             `Assoc
               [
                 ("observations", `List []);
                 ("regions", `List []);
               ] );
             ]))
  ;
  match
    decode
      (`Assoc
        [
          ( "failure",
            `Assoc
              [
                ("code", `String "parser-unavailable");
                ("message", `String "parser is unavailable");
                ( "data",
                  `Assoc
                    [
                      ("retryable", `Bool true);
                      ("attempt", `Int 2);
                    ] );
              ] );
        ])
    |> expect_ok
  with
  | Extension_protocol.Interpret_failure failure ->
      Alcotest.(check string) "interpret failure operation"
        "interpret-observation"
        (Extension_failure.operation failure
        |> Extension_failure.operation_string);
      Alcotest.(check string) "interpret failure code" "parser-unavailable"
        (Extension_failure.code failure);
      Alcotest.(check string) "interpret failure message" "parser is unavailable"
        (Extension_failure.message failure);
      Alcotest.(check string) "interpret failure canonical data"
        {|{"attempt":2,"retryable":true}|}
        (Extension_failure.data failure
        |> Option.get |> Yojson.Safe.to_string)
  | Extension_protocol.Interpretation _ ->
      Alcotest.fail "expected an extension interpretation failure"

let test_extension_annotation_extraction_result_validation () =
  let path = expect_ok (Workspace_path.of_canonical_string "docs/note.md") in
  let observation =
    Observation.of_bytes
      ~id:(expect_ok (Observation_id.make "observation:docs/note.md"))
      ~origin:(Observation.workspace path)
      ~observation_type:Observation_type.markdown ~bytes:"# Note\n"
  in
  let origin =
    `Assoc
      [
        ("kind", `String "workspace");
        ("path", `String "docs/note.md");
      ]
  in
  let scoped_id local =
    `Assoc [ ("scope", origin); ("local", `String local) ]
  in
  let whole_address =
    `Assoc
      [
        ("origin", origin);
        ("selector", `Assoc [ ("kind", `String "whole-observation") ]);
      ]
  in
  let source =
    `Assoc
      [
        ("kind", `String "observation");
        ("observation", `String "observation:docs/note.md");
        ( "locator",
          `Assoc
            [
              ("kind", `String "byte-range");
              ("range", `Assoc [ ("start", `Int 0); ("end", `Int 7) ]);
            ] );
        ( "encoding",
          `Assoc [ ("name", `String "test"); ("version", `String "1") ] );
      ]
  in
  let occurrence =
    `Assoc
      [
        ( "annotation",
          `Assoc
            [
              ("id", scoped_id "claim");
              ( "subject",
                `Assoc
                  [
                    ("kind", `String "address");
                    ("address", whole_address);
                  ] );
              ("predicate", `String "states");
              ( "object",
                `Assoc
                  [
                    ("kind", `String "literal");
                    ("value", `String "explicit");
                  ] );
            ] );
        ("source", source);
      ]
  in
  let result =
    `Assoc
      [
        ( "extraction",
          `Assoc [ ("occurrences", `List [ occurrence ]) ] );
      ]
  in
  (match
     Extension_protocol.decode_extract_annotations_result
       ~primary_observation:observation result
   with
  | Ok (Extension_protocol.Annotation_extraction extraction) ->
      Alcotest.(check int) "one typed annotation occurrence" 1
        (Annotation_extraction.occurrences extraction |> List.length)
  | Ok (Extension_protocol.Extract_annotations_failure _) ->
      Alcotest.fail "successful extraction decoded as a failure"
  | Error message -> Alcotest.fail message);
  let wrong_observation =
    `Assoc
      [
        ( "extraction",
          `Assoc
            [
              ( "occurrences",
                `List
                  [
                    `Assoc
                      [
                        ("annotation", List.assoc "annotation" (match occurrence with `Assoc fields -> fields | _ -> assert false));
                        ( "source",
                          `Assoc
                            [
                              ("kind", `String "observation");
                              ("observation", `String "observation:other.md");
                              ("locator", List.assoc "locator" (match source with `Assoc fields -> fields | _ -> assert false));
                              ("encoding", List.assoc "encoding" (match source with `Assoc fields -> fields | _ -> assert false));
                            ] );
                      ];
                  ] );
            ] );
      ]
  in
  check_error
    (Extension_protocol.decode_extract_annotations_result
       ~primary_observation:observation wrong_observation)

let test_extension_failure_diagnostic () =
  let failure =
    expect_ok
      (Extension_failure.make
         ~operation:Extension_failure.Interpret_observation
         ~code:"parser-unavailable" ~message:"parser is unavailable"
         ~data:(`Assoc [ ("retryable", `Bool true) ]) ())
  in
  let diagnostic =
    expect_ok
      (Diagnostic.make ~code:Diagnostic.Extension_failure
         ~message:(Extension_failure.message failure)
         ~extension_failure:failure ())
  in
  Alcotest.(check string) "extension failure diagnostic code"
    "extension-failure"
    (Diagnostic.code diagnostic |> Diagnostic.code_string);
  Alcotest.(check bool) "extension failure is retained" true
    (Diagnostic.extension_failure diagnostic = Some failure);
  check_error
    (Diagnostic.make ~code:Diagnostic.Extension_failure
       ~message:"missing structured failure" ());
  check_error
    (Diagnostic.make ~code:Diagnostic.Divergent
       ~message:(Extension_failure.message failure)
       ~extension_failure:failure ());
  check_error
    (Diagnostic.make ~code:Diagnostic.Unresolved_ref
       ~message:"different message" ~extension_failure:failure ());
  check_error
    (Extension_failure.make
       ~operation:Extension_failure.Interpret_observation
       ~code:"parser-unavailable" ~message:"parser is unavailable"
       ~data:(`Float 0.5) ())

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
  let protected = Command_boundary.protect (fun () -> invalid_arg "boom") in
  (match protected with
  | Ok () -> Alcotest.fail "unexpected exception escaped the command boundary"
  | Error result ->
      Alcotest.(check string) "exception boundary status" "internal-error"
        (Command_result.status result |> Command_result.status_string);
      Alcotest.(check string) "exception boundary exit class" "internal-error"
        (Command_result.exit_class result |> Command_result.exit_class_string));
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
         ~changed_files:
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
       ~changed_files:
         [ { Command_result.path = changed_path; before = Some before; after } ]
       ());
  check_error
    (Command_result.make ~command:"apply"
       ~termination:Command_result.Completed ~effect:Command_result.Applied
       ~changed_files:
         [ { Command_result.path = changed_path; before = Some before; after } ]
       ~conflicts:[ conflict ] ());
  check_error
    (Command_result.make ~command:"apply"
       ~termination:Command_result.Completed ~effect:Command_result.Conflicted
       ~conflicts:[ conflict ]
       ~changed_files:
         [ { Command_result.path = changed_path; before = Some before; after } ]
       ());
  check_error
    (Command_result.make ~command:"derive"
       ~termination:Command_result.Completed
       ~effect:Command_result.Patches_proposed ~patches:[ patch ]
       ~changed_files:
         [ { Command_result.path = changed_path; before = Some before; after } ]
       ());
  check_error
    (Command_result.make ~command:"apply"
       ~termination:(Command_result.Usage_failure "bad")
       ~effect:Command_result.Applied
       ~changed_files:
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
  let observation_a = expect_ok (Observation_id.make "observation:a") in
  let observation_b = expect_ok (Observation_id.make "observation:b") in
  let diagnostic observation code message =
    expect_ok
      (Diagnostic.make ~code ~message
         ~location:
           {
             Diagnostic.observation = Some observation;
             region = None;
             annotation = None;
             range = None;
           }
         ())
  in
  let first =
    diagnostic observation_b Diagnostic.Unresolved_ref "second observation"
  in
  let second = diagnostic observation_a Diagnostic.Duplicate "first observation" in
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
      "changedFiles";
      "conflicts";
      "snapshots";
      "observations";
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

let markdown_observation canonical_path content =
  let path = path canonical_path in
  let id =
    expect_ok (Observation_id.make ("observation:" ^ canonical_path))
  in
  Observation.of_bytes ~id ~origin:(Observation.workspace path)
    ~observation_type:Observation_type.markdown ~bytes:content

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
  | Workspace_ops.Internal_error _ -> Alcotest.fail "unexpected internal error"

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
         ~content ~reason:"create workspace observation" ~provenance)
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
    | Workspace_ops.Internal_error _ -> Alcotest.fail "create failed internally"
  in
  (match Workspace_ops.apply_patch created patch with
  | Workspace_ops.No_change _ -> ()
  | Workspace_ops.Applied _ | Workspace_ops.Conflict _
  | Workspace_ops.Internal_error _ ->
      Alcotest.fail "reapplying create patch must be a no-op");
  let occupied =
    expect_ok (Workspace_snapshot.make [ (target, "different\n") ])
  in
  match Workspace_ops.apply_patch occupied patch with
  | Workspace_ops.Conflict (Conflict.Target_already_exists _) -> ()
  | Workspace_ops.Applied _ | Workspace_ops.No_change _
  | Workspace_ops.Conflict _ | Workspace_ops.Internal_error _ ->
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
    | Workspace_ops.Applied _ | Workspace_ops.No_change _
    | Workspace_ops.Internal_error _ ->
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
  expect_conflict patch (function Conflict.Missing_target _ -> true | _ -> false)

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
  | Workspace_ops.Applied _ | Workspace_ops.Conflict _
  | Workspace_ops.Internal_error _ ->
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
  path "docs/note.annotations.yaml"

let decode_sidecar content =
  let snapshot = Sidecar_snapshot.of_bytes ~path:(sidecar_context ()) content in
  Sidecar_v2.decode snapshot

let valid_sidecar =
  {|version: 2
scope:
  origin:
    kind: workspace
    path: docs/note.md
authored:
  refs:
    run-a:
      target:
        origin:
          kind: workspace
          path: runs/data.jsonl
        selector:
          kind: row-filter
          where:
            metric: latency
            attempt: 1
        interpreter: jsonl
        interpreterVersion: "1"
      binding:
        mode: pinned
      expect:
        - digest: sha256:aafdf097b034d51e1794cb111ce16c46f88e9ef17da6f859a00fd39288e69ef6
  annotations:
    supported:
      subject:
        origin:
          kind: workspace
          path: docs/note.md
        selector:
          kind: region-id
          id: claim
        interpreter: markdown
        interpreterVersion: "1"
      predicate: supported-by
      object:
        ref: run-a
derived:
  refs: {}
  annotations: {}
|}

let test_sidecar_v2_strict_decode () =
  check_error
    (decode_sidecar
       {|version: 2
scope:
  origin:
    kind: workspace
    path: docs/note.md
authored:
  refs:
    incomplete:
      target:
        origin:
          kind: workspace
          path: runs/data.jsonl
        selector:
          kind: region-id
          id: row
        interpreter: jsonl
      binding:
        mode: tracking
  annotations: {}
derived:
  refs: {}
  annotations: {}
|});
  let decoded = expect_ok (decode_sidecar valid_sidecar) in
  let references = Sidecar_contents.reference_definitions decoded in
  let annotations = Sidecar_contents.annotations decoded in
  Alcotest.(check int) "reference occurrence count" 1
    (List.length references);
  Alcotest.(check int) "annotation occurrence count" 1
    (List.length annotations);
  let reference =
    List.hd references |> Reference_definition_occurrence.reference
  in
  Alcotest.(check bool) "scope comes from root origin" true
    (Origin.equal
       (expect_ok
          (Workspace_path.of_segments [ "docs"; "note.md" ])
        |> Observation.workspace)
       (Reference.id reference |> Reference_id.scope));
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
    "version: 2\nscope:\n  origin:\n    kind: workspace\n    path: docs/note.md\nauthored:\n  refs: {日本語: {}}\n  annotations: {}\nderived:\n  refs: {}\n  annotations: {}\n"
  in
  let range = expect_ok (Sidecar_edit.derived_section_range unicode) in
  Alcotest.(check string) "YAML character mark converts to byte offset"
    "derived:\n  refs: {}\n  annotations: {}\n"
    (String.sub unicode (Text_range.start range) (Text_range.length range));
  Alcotest.(check bool) "missing derived section" true
    (Option.is_none
       (expect_ok
          (Sidecar_edit.optional_derived_section_range
             "version: 2\nscope:\n  origin:\n    kind: workspace\n    path: docs/note.md\nauthored: {refs: {}, annotations: {}}\n")))

let test_sidecar_authored_overrides_derived () =
  let decoded =
    expect_ok
      (decode_sidecar
         {|version: 2
scope:
  origin:
    kind: workspace
    path: docs/note.md
authored:
  refs:
    run-a:
      target:
        origin:
          kind: workspace
          path: runs/authored.jsonl
        selector:
          kind: region-id
          id: authored
      binding:
        mode: pinned
  annotations: {}
derived:
  refs:
    run-a:
      target:
        origin:
          kind: workspace
          path: runs/derived.jsonl
        selector:
          kind: region-id
          id: derived
      binding:
        mode: tracking
  annotations: {}
|})
  in
  let definitions = Sidecar_contents.reference_definitions decoded in
  Alcotest.(check int) "both ownership records remain observable" 2
    (List.length definitions);
  let index = Reference_index.make definitions in
  Alcotest.(check int) "divergent ownership records form a conflict" 1
    (List.length (Reference_index.conflicts index));
  let ownerships =
    List.map
      (fun occurrence ->
        match Reference_definition_occurrence.source occurrence with
        | Source_location.In_sidecar source -> source.ownership
        | Source_location.In_observation _ ->
            Alcotest.fail "expected Sidecar source")
      definitions
  in
  Alcotest.(check bool) "authored ownership retained" true
    (List.mem Source_location.Authored ownerships);
  Alcotest.(check bool) "derived ownership retained" true
    (List.mem Source_location.Derived ownerships)

let test_sidecar_layout_profile () =
  ignore (expect_ok (decode_sidecar valid_sidecar));
  check_error
    (decode_sidecar
       "version: 2\nscope: {origin: {kind: workspace, path: docs/note.md}}\nauthored: {refs: {}, annotations: {}}\nderived: {refs: {}, annotations: {}}\n");
  check_error
    (decode_sidecar
       "{version: 2, scope: {origin: {kind: workspace, path: docs/note.md}}, authored: {refs: {}, annotations: {}}, derived: {refs: {}, annotations: {}}}\n");
  check_error
    (Sidecar_edit.validate_layout_profile
       "version: 2\nderived:\n  refs:\n    item: {target: {}, binding: {}}\n  annotations: {}\nauthored: {refs: {}, annotations: {}}\n")

let test_sidecar_v2_rejects_yaml_ambiguity () =
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
  ignore
    (expect_ok
       (decode_sidecar
          (replace "metric: latency" "metric: latency.p95" valid_sidecar)));
  check_error
    (decode_sidecar
       (replace "refs:" "refs:\n  duplicate: &shared {}\n  alias: *shared"
          valid_sidecar));
  check_error
    (decode_sidecar
       (replace "version: 2" "version: 2\nversion: 2" valid_sidecar));
  check_error
    (decode_sidecar (replace "attempt: 1" "attempt: 1.5" valid_sidecar));
  check_error
    (decode_sidecar
       (replace "metric: latency" "metric: !!str latency" valid_sidecar));
  check_error
    (decode_sidecar
       (replace "binding:" "procedure: run-this\n      binding:"
          valid_sidecar))

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

let test_workspace_inspect_conflicts_are_explicit () =
  with_temp_workspace (fun root ->
      Unix.mkdir (Filename.concat root "docs") 0o700;
      write_file (Filename.concat root "docs/note.md") markdown_fixture;
      write_file
        (Filename.concat root "docs/note.annotations.yaml")
        {|version: 2
scope:
  origin:
    kind: workspace
    path: docs/note.md
authored:
  refs:
    run-a:
      target:
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
        origin:
          kind: workspace
          path: docs/note.md
        selector:
          kind: region-id
          id: claim
        interpreter: markdown
        interpreterVersion: "1"
      predicate: user-selected
      object:
        ref: run-a
derived:
  refs:
    run-a:
      target:
        origin:
          kind: workspace
          path: runs/derived.jsonl
        selector:
          kind: region-id
          id: derived
      binding:
        mode: floating
  annotations: {}
|};
      let result =
        Workspace_inspect.inspect ~workspace:root ~observation:(path "docs/note.md")
      in
      Alcotest.(check string) "inspection completes" "diagnostics-found"
        (result_status result);
      Alcotest.(check int) "conflicting reference has no selected value" 0
        (List.length (Command_result.references result));
      Alcotest.(check int) "all reference definitions remain observable" 3
        (List.length (Command_result.reference_definitions result));
      Alcotest.(check int) "conflicting annotation has no selected value" 0
        (List.length (Command_result.annotations result));
      Alcotest.(check int) "all annotation occurrences remain observable" 2
        (List.length (Command_result.annotation_occurrences result));
      let codes =
        Command_result.diagnostics result |> List.map Diagnostic.code
      in
      Alcotest.(check int) "reference and annotation conflicts are explicit" 2
        (List.length
           (List.filter
              (fun code -> code = Diagnostic.Divergent)
              codes)))

let test_workspace_derive_create_apply_idempotent () =
  with_temp_workspace (fun root ->
      Unix.mkdir (Filename.concat root "docs") 0o700;
      write_file (Filename.concat root "docs/note.md") markdown_fixture;
      let first =
        Workspace_derive.derive_sidecar ~workspace:root
          ~observation:(path "docs/note.md")
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
      Alcotest.(check bool) "new sidecar declares v2 and its scope" true
        (String.starts_with
           ~prefix:
             "version: 2\nscope:\n  origin:\n    kind: workspace\n    path: \"docs/note.md\"\n"
           sidecar);
      Alcotest.(check bool) "new sidecar owns a derived section" true
        (try
           ignore
             (Str.search_forward (Str.regexp_string "derived:\n") sidecar 0);
           true
         with Not_found -> false);
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
          ~observation:(path "docs/note.md")
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
        ("version: 2\n"
        ^ "scope:\n  origin:\n    kind: workspace\n    path: docs/note.md\n"
        ^ authored ^ "derived:\n  refs: {}\n  annotations: {}\n");
      let derived =
        Workspace_derive.derive_sidecar ~workspace:root
          ~observation:(path "docs/note.md")
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
        ^ "  annotations: {\"手書き\": {subject: {origin: {kind: workspace, path: docs/note.md}, selector: {kind: region-id, id: claim}}, predicate: \"備考\", object: {ref: run-a}}}\n"
      in
      write_file
        (Filename.concat root "docs/note.annotations.yaml")
        ("version: 2\n"
        ^ "scope:\n  origin:\n    kind: workspace\n    path: docs/note.md\n"
        ^ "derived:\n  refs: {}\n  annotations: {}\n" ^ authored);
      let derived =
        Workspace_derive.derive_sidecar ~workspace:root
          ~observation:(path "docs/note.md")
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
  let observation = markdown_observation "docs/note.md" markdown_fixture in
  let inspected =
    expect_ok
      (Markdown_inspect.inspect ~observation markdown_fixture)
  in
  Alcotest.(check int) "region count" 1 (List.length inspected.regions);
  Alcotest.(check int) "reference count" 1
    (List.length inspected.reference_definitions);
  Alcotest.(check int) "annotation count" 1
    (List.length inspected.annotation_occurrences);
  let region = List.hd inspected.regions in
  Alcotest.(check string) "region ID" "claim"
    (Region.id region |> Region_id.local |> Identifier.to_string);
  let reference =
    List.hd inspected.reference_definitions
    |> Reference_definition_occurrence.reference
  in
  Alcotest.(check string) "link fragment is reference ID" "run-a"
    (Reference.id reference |> Reference_id.local |> Identifier.to_string);
  (match Reference.target_origin (Reference.target reference) with
  | Origin.Workspace target ->
      Alcotest.(check string) "relative link target" "runs/data.jsonl"
        (Workspace_path.to_canonical_string target)
  | _ -> Alcotest.fail "expected a workspace link target");
  let annotation =
    List.hd inspected.annotation_occurrences |> Annotation_occurrence.annotation
  in
  match Annotation.subject annotation with
  | Region_ref.Resolved subject ->
      Alcotest.(check bool) "annotation resolves preceding region" true
        (Region_id.equal subject (Region.id region))
  | Region_ref.Address _ -> Alcotest.fail "expected a resolved region subject"

let test_fixed_extension_markdown_observation () =
  let content =
    {|<!-- monika:region id=claim -->

Remote claim with a [self reference](#claim).
|}
  in
  let observer =
    expect_ok (Resource_observer.make ~name:"remote-docs" ~version:"1" ())
  in
  let origin =
    expect_ok
      (Observation.extension ~observer
         ~locator:(`Assoc [ ("document", `String "claim") ]) ())
  in
  let id = expect_ok (Observation_id.make "observation:remote-docs:claim") in
  let identity =
    expect_ok
      (Observation_identity.make ~observation_type:Observation_type.markdown
         ~key:"remote-revision:42" ())
  in
  let observation =
    expect_ok
      (Observation.make ~id ~origin ~identity
         ~representation:(Observation.Bytes content) ())
  in
  let inspection =
    Workspace_inspect.inspect_fixed_observation ~observation
      ~sidecar_snapshots:[] ~base_diagnostics:[]
    |> function
    | Ok inspection -> inspection
    | Error Workspace_inspect.Observation_changed ->
        Alcotest.fail "fixed external Observation was unexpectedly re-observed"
    | Error (Workspace_inspect.Invalid_observation message) ->
        Alcotest.fail message
  in
  Alcotest.(check string) "fixed external Markdown is interpreted" "ok"
    (result_status inspection.result);
  let regions = Command_result.regions inspection.result in
  Alcotest.(check int) "whole and marked regions" 2 (List.length regions);
  List.iter
    (fun region ->
      Alcotest.(check bool) "Observer-owned identity is retained" true
        (Observation_identity.equal identity
           (Region.observation_identity region)))
    regions;
  match Reference_index.consistent_values inspection.reference_index with
  | [ reference ] ->
      Alcotest.(check bool) "reference scope is the external Origin" true
        (Origin.equal origin (Reference.id reference |> Reference_id.scope))
  | _ -> Alcotest.fail "expected one external reference definition"

let test_markdown_reference_occurrences () =
  let content =
    {|<!-- monika:region id=claim -->

The claim links to [the whole file](../target.md) and [a named target](../target.md#target-region).
|}
  in
  let observation = markdown_observation "docs/source.md" content in
  let inspected =
    expect_ok (Markdown_inspect.inspect ~observation content)
  in
  Alcotest.(check int) "reference definition count" 1
    (List.length inspected.reference_definitions);
  Alcotest.(check int) "reference use count" 2
    (List.length inspected.reference_uses);
  let region = List.hd inspected.regions in
  List.iter
    (fun use ->
      match Reference_use.source_region use with
      | Reference_use.Region source ->
          Alcotest.(check bool) "occurrence belongs to containing region" true
            (Region_id.equal source (Region.id region))
      | Reference_use.Whole_observation ->
          Alcotest.fail "expected a containing source region")
    inspected.reference_uses;
  let direct =
    List.find
      (fun use ->
        match Reference_use.target use with
        | Reference_use.Direct _ -> true
        | Reference_use.Named _ -> false)
      inspected.reference_uses
  in
  (match Reference_use.target direct with
  | Reference_use.Direct address -> (
      match Region_address.origin address with
      | Origin.Workspace target ->
          Alcotest.(check string) "direct target path" "target.md"
            (Workspace_path.to_canonical_string target)
      | _ -> Alcotest.fail "expected a workspace target")
  | Reference_use.Named _ ->
      Alcotest.fail "expected a direct occurrence");
  let named =
    List.find
      (fun use ->
        match Reference_use.target use with
        | Reference_use.Named _ -> true
        | Reference_use.Direct _ -> false)
      inspected.reference_uses
  in
  match Reference_use.target named with
  | Reference_use.Named id ->
      Alcotest.(check string) "named occurrence reference ID" "target-region"
        (Reference_id.local id |> Identifier.to_string)
  | Reference_use.Direct _ ->
      Alcotest.fail "expected a named occurrence"

let repeated_markdown_reference_fixture =
  {|# Reproduction

[First use](#target)

[Second use](#target)

## Target

Target text.
|}

let test_markdown_repeated_reference_occurrences () =
  let observation =
    markdown_observation "README.md" repeated_markdown_reference_fixture
  in
  let inspected =
    expect_ok
      (Markdown_inspect.inspect ~observation repeated_markdown_reference_fixture)
  in
  Alcotest.(check int) "two definition occurrences" 2
    (List.length inspected.reference_definitions);
  Alcotest.(check int) "two syntactic occurrences" 2
    (List.length inspected.reference_uses);
  let index = Reference_index.make inspected.reference_definitions in
  Alcotest.(check int) "identical definitions yield one semantic value" 1
    (List.length (Reference_index.consistent_values index))

let test_workspace_repeated_reference_occurrences () =
  with_temp_workspace (fun root ->
      write_file (Filename.concat root "README.md")
        repeated_markdown_reference_fixture;
      let result =
        Workspace_inspect.inspect ~workspace:root ~observation:(path "README.md")
      in
      Alcotest.(check string) "inspection completes" "ok"
        (result_status result);
      Alcotest.(check int) "one named reference declaration" 1
        (List.length (Command_result.references result));
      let checked = Workspace_check.check ~workspace:root in
      Alcotest.(check string) "check returns a structured result"
        "diagnostics-found" (result_status checked))

let test_markdown_divergent_repeated_reference () =
  let content =
    "[First target](one.md#target)\n\n[Second target](two.md#target)\n"
  in
  let observation = markdown_observation "README.md" content in
  let inspected =
    expect_ok (Markdown_inspect.inspect ~observation content)
  in
  Alcotest.(check int) "both divergent definitions remain observable" 2
    (List.length inspected.reference_definitions);
  Alcotest.(check int) "divergence forms one index conflict" 1
    (List.length
       (Reference_index.make inspected.reference_definitions
       |> Reference_index.conflicts));
  with_temp_workspace (fun root ->
      write_file (Filename.concat root "README.md") content;
      let result =
        Workspace_inspect.inspect ~workspace:root ~observation:(path "README.md")
      in
      Alcotest.(check string) "divergence is a diagnostic result"
        "diagnostics-found" (result_status result);
      match Command_result.diagnostics result with
      | [ diagnostic ] ->
          Alcotest.(check string) "diagnostic code" "divergent"
            (Diagnostic.code diagnostic |> Diagnostic.code_string)
      | _ -> Alcotest.fail "expected exactly one divergence diagnostic")

let test_relation_projection_from_annotation () =
  let observation = markdown_observation "docs/note.md" markdown_fixture in
  let inspected =
    expect_ok
      (Markdown_inspect.inspect ~observation markdown_fixture)
  in
  let annotation =
    List.hd inspected.annotation_occurrences |> Annotation_occurrence.annotation
  in
  let occurrence = List.hd inspected.annotation_occurrences in
  let entry =
    Annotation_index.Consistent
      { value = annotation; occurrences = Nonempty.singleton occurrence }
  in
  match Relation.of_index_entry entry with
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
          (Workspace_graph.query ~workspace:root ~observation:(path "target.md")
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
      Alcotest.(check int) "scanned observations" 2
        (Coverage.primary_resources coverage);
      Alcotest.(check int) "interpreted observations" 2
        (Coverage.interpreted coverage);
      Alcotest.(check bool) "complete coverage" true
        (Coverage.complete coverage);
      let limited =
        expect_query
          (Workspace_graph.query ~workspace:root ~observation:(path "target.md")
             ~direction:Workspace_graph.Both ~predicate:None ~limit:2)
      in
      Alcotest.(check int) "limit" 2
        (List.length (Workspace_graph.matches limited));
      Alcotest.(check bool) "truncation is explicit" true
        (Workspace_graph.truncated limited);
      let target_region = expect_ok (Identifier.make "target-region") in
      let region_related =
        expect_query
          (Workspace_graph.query_for_region ~workspace:root
             ~observation:(path "target.md") ~region:target_region
             ~scope:Workspace_graph.Exact ~direction:Workspace_graph.Both
             ~predicate:None ~limit:50)
      in
      Alcotest.(check int)
        "exact region excludes the whole-observation target" 2
        (List.length (Workspace_graph.matches region_related));
      Alcotest.(check (option string)) "query region is retained"
        (Some "target-region")
        (Workspace_graph.query_region region_related
        |> Option.map Identifier.to_string))

let test_markdown_inspect_rejects_invalid_directives () =
  let inspect content =
    let observation = markdown_observation "docs/note.md" content in
    Markdown_inspect.inspect ~observation content
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
  let repeated =
    expect_ok
      (inspect
         "<!-- monika:region id=region -->\n\ntext\n\n<!-- monika:annotation id=same predicate=p ref=r -->\n\n<!-- monika:annotation id=same predicate=p ref=r -->\n")
  in
  Alcotest.(check int) "duplicate occurrences are retained" 2
    (List.length repeated.annotation_occurrences)

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
          (Some
             (if Sys.win32 then "reparse-point" else "symlink-component"))
          (filesystem_safety_reason result);
        Alcotest.(check string) "symlink parent does not rewrite referent" "abc"
          (read_file real));
    if not Sys.win32 then
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
            (List.length (Command_result.observations scan))))

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
    (Filesystem_stable_read.retry ~attempts:Filesystem_stable_read.twice
       ~on_unstable:"unstable" attempt);
  Alcotest.(check int) "two attempts" 2 !attempts;
  attempts := 0;
  let always_changed () =
    incr attempts;
    Ok Filesystem_stable_read.Changed
  in
  Alcotest.(check (result string string)) "repeated mutation fails"
    (Error "unstable")
    (Filesystem_stable_read.retry ~attempts:Filesystem_stable_read.twice
       ~on_unstable:"unstable"
       always_changed);
  Alcotest.(check int) "retry remains bounded" 2 !attempts;
  check_error (Filesystem_stable_read.make_attempts 0)

let observation_paths result =
  result |> Command_result.observations
  |> List.map (fun observation ->
         Observation.origin observation |> function
         | Origin.Workspace path -> Workspace_path.to_canonical_string path
         | _ -> Alcotest.fail "expected workspace observation")
  |> List.sort String.compare

let test_workspace_ignore_pattern_semantics () =
  let patterns =
    {|# generated output
*.log
!/keep.log
/root-only.txt
docs/*.tmp
cache/**
build/
file?.[oa]
a/**/b
name[!0-9].txt
digit[[:digit:]].txt
foo/*
|}
    ^ "plain   \nescaped\\ \n"
    ^ {|\#literal
\!literal
|}
  in
  let rules =
    Workspace_ignore.empty
    |> Workspace_ignore.add_patterns ~base:None patterns
  in
  let ignored ?(directory = false) value =
    Workspace_ignore.is_ignored rules ~path:(path value) ~directory
  in
  Alcotest.(check bool) "unanchored basename" true
    (ignored "nested/debug.log");
  Alcotest.(check bool) "later negation" false (ignored "keep.log");
  Alcotest.(check bool) "negation remains root-relative" true
    (ignored "nested/keep.log");
  Alcotest.(check bool) "root anchor" true (ignored "root-only.txt");
  Alcotest.(check bool) "root anchor excludes nested path" false
    (ignored "nested/root-only.txt");
  Alcotest.(check bool) "single star does not cross separator" true
    (ignored "docs/generated.tmp");
  Alcotest.(check bool) "path pattern remains relative to rule file" false
    (ignored "nested/docs/generated.tmp");
  Alcotest.(check bool) "trailing double star matches descendants" true
    (ignored "cache/a/b/value");
  Alcotest.(check bool) "trailing double star excludes contents, not parent"
    false (ignored ~directory:true "cache");
  Alcotest.(check bool) "directory-only pattern" true
    (ignored ~directory:true "nested/build");
  Alcotest.(check bool) "directory-only pattern does not match regular file"
    false (ignored "build");
  Alcotest.(check bool) "question and character class" true
    (ignored "file1.o");
  Alcotest.(check bool) "double star matches zero directories" true
    (ignored "a/b");
  Alcotest.(check bool) "double star matches multiple directories" true
    (ignored "a/x/y/b");
  Alcotest.(check bool) "negated character class" true
    (ignored "namex.txt");
  Alcotest.(check bool) "negated character class rejects member" false
    (ignored "name7.txt");
  Alcotest.(check bool) "POSIX named character class" true
    (ignored "digit7.txt");
  Alcotest.(check bool) "path star matches one component" true
    (ignored "foo/value");
  Alcotest.(check bool) "path star does not cross separator" false
    (ignored "foo/bar/value");
  Alcotest.(check bool) "unescaped trailing spaces are removed" true
    (ignored "plain");
  Alcotest.(check bool) "escaped trailing space is literal" true
    (ignored "escaped ");
  Alcotest.(check bool) "escaped comment prefix" true (ignored "#literal");
  Alcotest.(check bool) "escaped negation prefix" true (ignored "!literal")

let test_workspace_ignore_nested_precedence () =
  let parent =
    Workspace_ignore.empty
    |> Workspace_ignore.add_patterns ~base:None "*.tmp\n*.log\n"
  in
  let nested =
    parent
    |> Workspace_ignore.add_patterns ~base:(Some (path "docs"))
         "!keep.tmp\n/generated/\n"
  in
  let ignored rules ?(directory = false) value =
    Workspace_ignore.is_ignored rules ~path:(path value) ~directory
  in
  Alcotest.(check bool) "parent rule applies below its directory" true
    (ignored nested "docs/drop.tmp");
  Alcotest.(check bool) "nested negation overrides parent" false
    (ignored nested "docs/keep.tmp");
  Alcotest.(check bool) "nested pattern does not affect sibling" false
    (ignored nested ~directory:true "generated");
  Alcotest.(check bool) "nested anchored directory" true
    (ignored nested ~directory:true "docs/generated");
  Alcotest.(check bool) "parent value remains immutable" true
    (ignored parent "docs/keep.tmp")

let test_workspace_scan_ignore_files () =
  with_temp_workspace (fun root ->
      Unix.mkdir (Filename.concat root "build") 0o700;
      Unix.mkdir (Filename.concat root ".git") 0o700;
      write_file (Filename.concat root ".gitignore") "*.tmp\nbuild/\n";
      write_file (Filename.concat root ".monikaignore")
        "!/keep.tmp\nsecret.md\n";
      write_file (Filename.concat root "drop.tmp") "ignored";
      write_file (Filename.concat root "keep.tmp") "included";
      write_file (Filename.concat root "keep.txt") "included";
      write_file (Filename.concat root "secret.md") "ignored";
      write_file (Filename.concat (Filename.concat root "build") "output.bin")
        "ignored";
      write_file (Filename.concat (Filename.concat root ".git") "HEAD")
        "ignored metadata";
      let result = Workspace_scan.scan ~workspace:root in
      Alcotest.(check string) "status" "ok" (result_status result);
      Alcotest.(check (list string))
        "gitignore, monika override, and VCS metadata exclusion"
        [ ".gitignore"; ".monikaignore"; "keep.tmp"; "keep.txt" ]
        (observation_paths result))

let test_workspace_scan_nested_ignore_files () =
  with_temp_workspace (fun root ->
      let docs = Filename.concat root "docs" in
      Unix.mkdir docs 0o700;
      Unix.mkdir (Filename.concat docs "generated") 0o700;
      write_file (Filename.concat root ".gitignore") "*.tmp\n";
      write_file (Filename.concat docs ".gitignore")
        "!keep.tmp\n/generated/\n";
      write_file (Filename.concat root "root.tmp") "ignored";
      write_file (Filename.concat docs "drop.tmp") "ignored";
      write_file (Filename.concat docs "keep.tmp") "included";
      write_file (Filename.concat docs "note.md") "included";
      write_file (Filename.concat (Filename.concat docs "generated") "data.bin")
        "ignored";
      let result = Workspace_scan.scan ~workspace:root in
      Alcotest.(check string) "status" "ok" (result_status result);
      Alcotest.(check (list string)) "nested precedence and anchored directory"
        [ ".gitignore"; "docs/.gitignore"; "docs/keep.tmp"; "docs/note.md" ]
        (observation_paths result))

let test_workspace_check_uses_scan_ignore_rules () =
  with_temp_workspace (fun root ->
      write_file (Filename.concat root ".gitignore") "ignored.md\n";
      write_file (Filename.concat root "ignored.md")
        "<!-- monika:unknown id=invalid -->\n";
      write_file (Filename.concat root "visible.md") "# Visible\n";
      let result = Workspace_check.check ~workspace:root in
      Alcotest.(check string) "ignored invalid Markdown is not interpreted" "ok"
        (result_status result);
      Alcotest.(check (list string)) "check inventory follows scan"
        [ ".gitignore"; "visible.md" ] (observation_paths result))

let test_workspace_scan_regular_files () =
  with_temp_workspace (fun root ->
      Unix.mkdir (Filename.concat root "docs") 0o700;
      write_file (Filename.concat root "b.txt") "b";
      write_file (Filename.concat root "a.txt") "a";
      write_file (Filename.concat (Filename.concat root "docs") "note.md") "# Note\n";
      let result = Workspace_scan.scan ~workspace:root in
      Alcotest.(check string) "status" "ok" (result_status result);
      Alcotest.(check string) "exitClass" "success" (result_exit_class result);
      Alcotest.(check (list string)) "stable observation paths"
        [ "a.txt"; "b.txt"; "docs/note.md" ]
        (observation_paths result);
      Alcotest.(check int) "observation count" 3
        (List.length (Command_result.observations result));
      let markdown =
        Command_result.observations result
        |> List.find (fun observation ->
               match Observation.origin observation with
               | Origin.Workspace path ->
                   String.equal
                     (Workspace_path.to_canonical_string path)
                     "docs/note.md"
               | _ -> false)
      in
      Alcotest.(check string) "resource observer fixes the Markdown observation type"
        "text/markdown"
        (Observation.observation_type markdown |> Observation_type.name))

let test_existing_observation_is_fixed_before_interpretation () =
  with_temp_workspace (fun root ->
      let content = "# Note\n" in
      write_file (Filename.concat root "note.md") content;
      let path = path "note.md" in
      let id = expect_ok (Observation_id.make "observation:note.md") in
      let binary_observation =
        Observation.of_bytes ~id ~origin:(Observation.workspace path)
          ~observation_type:Observation_type.binary
          ~bytes:content
      in
      (match
         Workspace_inspect.inspect_existing_observation ~workspace:root
           ~observation:binary_observation
       with
      | Error _ -> Alcotest.fail "fixed binary observation could not be read"
      | Ok inspection ->
          Alcotest.(check string) "binary observation is not reclassified"
            "diagnostics-found" (result_status inspection.result));
      let markdown_observation =
        Observation.of_bytes ~id ~origin:(Observation.workspace path)
          ~observation_type:Observation_type.markdown
          ~bytes:content
      in
      write_file (Filename.concat root "note.md") "# Changed\n";
      match
        Workspace_inspect.inspect_existing_observation ~workspace:root
          ~observation:markdown_observation
      with
      | Error Workspace_inspect.Observation_changed -> ()
      | Error (Workspace_inspect.Invalid_observation message) ->
          Alcotest.fail message
      | Ok _ ->
          Alcotest.fail
            "changed content was interpreted as the fixed observation")

let test_workspace_scan_chunked_identity () =
  with_temp_workspace (fun root ->
      let content =
        String.init ((65536 * 2) + 17) (fun index -> Char.chr (index mod 251))
      in
      write_file (Filename.concat root "large.bin") content;
      let result = Workspace_scan.scan ~workspace:root in
      Alcotest.(check string) "status" "ok" (result_status result);
      match Command_result.observations result with
      | [ observation ] ->
          Alcotest.(check bool) "identity crosses multiple read chunks" true
            (Option.equal Content_identity.equal
               (Observation.content_identity observation)
               (Some (Content_identity.of_content content)))
      | _ -> Alcotest.fail "expected exactly one observation")

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
          [ "target.txt" ] (observation_paths result);
        Alcotest.(check int) "one diagnostic" 1
          (List.length (Command_result.diagnostics result));
        match Command_result.diagnostics result with
        | [ diagnostic ] ->
            Alcotest.(check string) "filesystem-specific diagnostic code"
              "unsupported-filesystem-entry"
              (Diagnostic.code diagnostic |> Diagnostic.code_string)
        | _ -> Alcotest.fail "expected exactly one diagnostic")

let test_workspace_scan_does_not_follow_ignore_symlink () =
  if not Sys.win32 then
    with_temp_workspace (fun root ->
        write_file (Filename.concat root "rules") "*.tmp\n";
        write_file (Filename.concat root "visible.tmp") "visible";
        Unix.symlink "rules" (Filename.concat root ".gitignore");
        let result = Workspace_scan.scan ~workspace:root in
        Alcotest.(check string) "status" "diagnostics-found"
          (result_status result);
        Alcotest.(check (list string))
          "symlinked ignore file is not read as configuration"
          [ "rules"; "visible.tmp" ] (observation_paths result);
        match Command_result.diagnostics result with
        | [ diagnostic ] ->
            Alcotest.(check string) "symlink remains an unsupported entry"
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
          [ "file.txt" ] (observation_paths result))

let test_workspace_scan_special_entry_diagnostic () =
  if not Sys.win32 then
    with_temp_workspace (fun root ->
        Unix.mkfifo (Filename.concat root "events.fifo") 0o600;
        let result = Workspace_scan.scan ~workspace:root in
        Alcotest.(check string) "status" "diagnostics-found"
          (result_status result);
        Alcotest.(check (list string)) "special entry is not an observation" []
          (observation_paths result);
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
            Alcotest.(check string) "unreadable file status" "diagnostics-found"
              (result_status result);
            Alcotest.(check string) "unreadable file exitClass"
              "diagnostic-error" (result_exit_class result);
            let coverage = Command_result.coverage result in
            Alcotest.(check int) "unreadable resource was discovered" 1
              (Coverage.primary_resources coverage);
            Alcotest.(check int) "unreadable resource was not observed" 0
              (Coverage.observed coverage);
            Alcotest.(check int) "observation failure is covered" 1
              (Coverage.failed coverage);
            match Command_result.diagnostics result with
            | [ diagnostic ] ->
                Alcotest.(check string) "observation failure diagnostic"
                  "observation-failure"
                  (Diagnostic.code diagnostic |> Diagnostic.code_string)
            | _ -> Alcotest.fail "expected one observation failure"));
    with_temp_workspace (fun root ->
        let file = Filename.concat root "note.annotations.yaml" in
        write_file file "version: 2\n";
        Fun.protect
          ~finally:(fun () -> Unix.chmod file 0o600)
          (fun () ->
            Unix.chmod file 0o000;
            let result = Workspace_scan.scan ~workspace:root in
            Alcotest.(check string) "unreadable metadata status"
              "diagnostics-found" (result_status result);
            let coverage = Command_result.coverage result in
            Alcotest.(check int) "metadata candidate was discovered" 1
              (Coverage.metadata_discovered coverage);
            Alcotest.(check int) "metadata was not decoded" 0
              (Coverage.metadata_decoded coverage);
            Alcotest.(check int) "metadata read failure is covered" 1
              (Coverage.metadata_failed coverage);
            match Command_result.diagnostics result with
            | [ diagnostic ] ->
                Alcotest.(check string) "metadata failure diagnostic"
                  "metadata-failure"
                  (Diagnostic.code diagnostic |> Diagnostic.code_string)
            | _ -> Alcotest.fail "expected one metadata failure"));
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
          Alcotest.test_case "region extent relation" `Quick
            test_region_extent_relation;
          Alcotest.test_case "installed extension registry" `Quick
            test_registry_snapshot;
          Alcotest.test_case "resource and observation abstractions" `Quick
            test_resource_observation_abstractions;
          Alcotest.test_case "scoped identifiers and region address" `Quick
            test_scoped_identifiers_and_region_address;
          Alcotest.test_case "range" `Quick test_range;
          Alcotest.test_case "patch" `Quick test_patch;
          Alcotest.test_case "observation origin and reference target" `Quick
            test_observation_origin_and_reference_target;
          Alcotest.test_case "selector and expectation" `Quick
            test_selector_and_expectation;
          Alcotest.test_case "diagnostic severity" `Quick
            test_diagnostic_severity;
          Alcotest.test_case "command result" `Quick test_command_result;
          Alcotest.test_case "capability" `Quick test_capability;
          Alcotest.test_case "extension applicability" `Quick
            test_extension_applicability;
          Alcotest.test_case "extension manifest" `Quick
            test_extension_manifest;
          Alcotest.test_case "extension resolve result validation" `Quick
            test_extension_resolve_result_validation;
          Alcotest.test_case "extension interpretation result validation" `Quick
            test_extension_interpretation_result_validation;
          Alcotest.test_case "extension annotation extraction validation" `Quick
            test_extension_annotation_extraction_result_validation;
          Alcotest.test_case "extension failure diagnostic" `Quick
            test_extension_failure_diagnostic;
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
          Alcotest.test_case "gitignore-compatible pattern semantics" `Quick
            test_workspace_ignore_pattern_semantics;
          Alcotest.test_case "nested ignore precedence" `Quick
            test_workspace_ignore_nested_precedence;
          Alcotest.test_case "automatic ignore files" `Quick
            test_workspace_scan_ignore_files;
          Alcotest.test_case "nested automatic ignore files" `Quick
            test_workspace_scan_nested_ignore_files;
          Alcotest.test_case "check uses scan ignore rules" `Quick
            test_workspace_check_uses_scan_ignore_rules;
          Alcotest.test_case "regular files" `Quick
            test_workspace_scan_regular_files;
          Alcotest.test_case "observation is fixed before interpretation" `Quick
            test_existing_observation_is_fixed_before_interpretation;
          Alcotest.test_case "chunked content identity" `Quick
            test_workspace_scan_chunked_identity;
          Alcotest.test_case "invalid roots" `Quick
            test_workspace_scan_invalid_roots;
          Alcotest.test_case "symlink diagnostic" `Quick
            test_workspace_scan_symlink_diagnostic;
          Alcotest.test_case "ignore symlink is not followed" `Quick
            test_workspace_scan_does_not_follow_ignore_symlink;
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
          Alcotest.test_case "strict sidecar v2" `Quick
            test_sidecar_v2_strict_decode;
          Alcotest.test_case "sidecar edit location" `Quick
            test_sidecar_annotation_insertion_offset;
          Alcotest.test_case "ownership conflicts remain explicit" `Quick
            test_sidecar_authored_overrides_derived;
          Alcotest.test_case "sidecar layout profile" `Quick
            test_sidecar_layout_profile;
          Alcotest.test_case "rejects ambiguous YAML" `Quick
            test_sidecar_v2_rejects_yaml_ambiguity;
          Alcotest.test_case "inspection conflicts are explicit" `Quick
            test_workspace_inspect_conflicts_are_explicit;
          Alcotest.test_case "derive create/apply/idempotency" `Quick
            test_workspace_derive_create_apply_idempotent;
          Alcotest.test_case "derive preserves authored bytes" `Quick
            test_workspace_derive_preserves_authored_bytes;
          Alcotest.test_case "CommonMark observations" `Quick
            test_markdown_inspect_commonmark;
          Alcotest.test_case "fixed external CommonMark Observation" `Quick
            test_fixed_extension_markdown_observation;
          Alcotest.test_case "CommonMark reference occurrences" `Quick
            test_markdown_reference_occurrences;
          Alcotest.test_case "repeated CommonMark reference occurrences" `Quick
            test_markdown_repeated_reference_occurrences;
          Alcotest.test_case "inspect and check repeated CommonMark references"
            `Quick test_workspace_repeated_reference_occurrences;
          Alcotest.test_case "rejects divergent repeated references" `Quick
            test_markdown_divergent_repeated_reference;
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
