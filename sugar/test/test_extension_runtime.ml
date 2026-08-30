open Monika_sugar

let expect_ok = function
  | Ok value -> value
  | Error failure ->
      Alcotest.failf "unexpected runtime failure [%s]: %s"
        (Extension_runtime.failure_code failure)
        (Extension_runtime.failure_message failure)

let manifest () =
  Extension_manifest.of_yojson
    (`Assoc
      [
        ("protocolVersion", `String "1");
        ( "capability",
          `Assoc
            [
              ("type", `String "interpreter");
              ("name", `String "custom-markdown");
              ("version", `String "1");
              ( "appliesTo",
                `Assoc
                  [
                    ("mediaTypes", `List [ `String "text/markdown" ]);
                    ("pathGlobs", `List [ `String "docs/*.md" ]);
                  ] );
              ( "schemas",
                `Assoc
                  [
                    ( "selector",
                      `String
                        "https://example.invalid/schemas/custom-markdown-selector-v1.json"
                    );
                  ] );
            ] );
      ])
  |> Result.get_ok

let limits ?(max_message_bytes = 16 * 1024 * 1024)
    ?(request_timeout_ms = 1_000) ?(shutdown_timeout_ms = 1_000) () =
  Extension_runtime.make_limits ~max_message_bytes ~request_timeout_ms
    ~shutdown_timeout_ms ()
  |> Result.get_ok

let run peer mode ?(limits = limits ()) operation =
  Extension_runtime.with_session ~executable:peer ~arguments:[ mode ] ~limits
    operation

let expect_failure_code expected = function
  | Ok _ -> Alcotest.failf "expected runtime failure %s" expected
  | Error failure ->
      Alcotest.(check string) "failure code" expected
        (Extension_runtime.failure_code failure)

let expect_remote_failure_data = function
  | Ok _ -> Alcotest.fail "expected remote runtime failure"
  | Error failure ->
      Alcotest.(check string) "remote failure data"
        {|{"jsonRpcCode":-32001,"data":{"retryable":false}}|}
        (Extension_runtime.failure_data failure
        |> Option.get |> Yojson.Safe.to_string)

let test_initialize_session peer () =
  let runtime_manifest =
    run peer "good" (fun session ->
        Extension_runtime.initialize_session session)
    |> expect_ok
  in
  Alcotest.(check bool) "runtime manifest equals static manifest" true
    (Extension_manifest.equal runtime_manifest (manifest ()));
  let mismatched =
    run peer "mismatch" (fun session ->
        Extension_runtime.initialize_session session)
    |> expect_ok
  in
  Alcotest.(check bool) "different capability is not equal" false
    (Extension_manifest.equal mismatched (manifest ()))

let test_generic_call peer () =
  let params = `Assoc [ ("enabled", `Bool true); ("count", `Int 3) ] in
  let result =
    run peer "echo" (fun session ->
        match Extension_runtime.initialize_session session with
        | Error _ as error -> error
        | Ok _ ->
            Extension_runtime.call session ~method_name:"monika.echo" ~params)
    |> expect_ok
  in
  Alcotest.(check string) "result"
    {|{"count":3,"enabled":true}|}
    (Yojson.Safe.to_string result);
  run peer "good" (fun session ->
      Extension_runtime.call session ~method_name:"monika.echo" ~params)
  |> expect_failure_code "session-not-initialized";
  run peer "good" (fun session ->
      match Extension_runtime.initialize_session session with
      | Error _ as error -> error
      | Ok _ ->
      Extension_runtime.call session ~method_name:"other.echo" ~params)
  |> expect_failure_code "invalid-request";
  run peer "good" (fun session ->
      match Extension_runtime.initialize_session session with
      | Error _ as error -> error
      | Ok _ ->
          Extension_runtime.call session ~method_name:"monika.echo"
            ~params:(`Float 1.5))
  |> expect_failure_code "invalid-request";
  let rec nested depth =
    if depth = 0 then `Null else `List [ nested (depth - 1) ]
  in
  run peer "good" (fun session ->
      match Extension_runtime.initialize_session session with
      | Error _ as error -> error
      | Ok _ ->
          Extension_runtime.call session ~method_name:"monika.echo"
            ~params:(nested 129))
  |> expect_failure_code "invalid-request"

let test_checked_session peer () =
  Extension_runtime.with_checked_session ~executable:peer ~arguments:[ "good" ]
    ~limits:(limits ()) ~manifest:(manifest ()) (fun _ -> Ok ())
  |> expect_ok;
  Extension_runtime.with_checked_session ~executable:peer
    ~arguments:[ "mismatch" ] ~limits:(limits ()) ~manifest:(manifest ())
    (fun _ -> Ok ())
  |> expect_failure_code "manifest-mismatch"

let test_content_stream peer () =
  let content =
    String.init 100_000 (fun index -> Char.chr (index mod 256))
  in
  let result =
    run peer "stream" (fun session ->
        match Extension_runtime.initialize_session session with
        | Error _ as error -> error
        | Ok _ ->
            Extension_runtime.call_with_content session
              ~method_name:"monika.streamTest"
              ~params:(`Assoc [ ("purpose", `String "transport-test") ])
              ~content)
    |> expect_ok
  in
  let open Yojson.Safe.Util in
  Alcotest.(check int) "byte length" 100_000
    (result |> member "byteLength" |> to_int);
  Alcotest.(check bool) "more than one bounded chunk" true
    (result |> member "chunks" |> to_int > 1);
  Alcotest.(check bool) "exact bytes" true
    (result |> member "matches" |> to_bool)

let test_response_validation peer () =
  run peer "wrong-id" (fun session ->
      Extension_runtime.initialize_session session)
  |> expect_failure_code "invalid-response";
  run peer "invalid-json" (fun session ->
      Extension_runtime.initialize_session session)
  |> expect_failure_code "invalid-response";
  run peer "duplicate-field" (fun session ->
      Extension_runtime.initialize_session session)
  |> expect_failure_code "invalid-response";
  run peer "remote-error" (fun session ->
      Extension_runtime.initialize_session session)
  |> expect_remote_failure_data;
  run peer "remote-error-null" (fun session ->
      Extension_runtime.initialize_session session)
  |> expect_failure_code "remote-error"

let test_limits peer () =
  run peer "oversized"
    ~limits:(limits ~max_message_bytes:512 ())
    (fun session -> Extension_runtime.initialize_session session)
  |> expect_failure_code "response-too-large";
  run peer "timeout"
    ~limits:(limits ~request_timeout_ms:50 ())
    (fun session -> Extension_runtime.initialize_session session)
  |> expect_failure_code "timeout";
  run peer "low-message-limit" (fun session ->
      match Extension_runtime.initialize_session session with
      | Error _ as error -> error
      | Ok _ ->
          Extension_runtime.call session ~method_name:"monika.echo"
            ~params:(`String (String.make 600 'x')))
  |> expect_failure_code "request-too-large"

let test_process_completion peer () =
  run peer "nonzero-after-response" (fun session ->
      Extension_runtime.initialize_session session)
  |> expect_failure_code "process-exit";
  run peer "no-exit-after-eof"
    ~limits:(limits ~shutdown_timeout_ms:50 ())
    (fun session -> Extension_runtime.initialize_session session)
  |> expect_failure_code "shutdown-timeout";
  run peer "good" (fun _ -> invalid_arg "host callback failed")
  |> expect_failure_code "host-operation-exception"

let test_limits_validation () =
  Alcotest.(check bool) "zero message limit is rejected" true
    (Result.is_error
       (Extension_runtime.make_limits ~max_message_bytes:0
          ~request_timeout_ms:1_000 ~shutdown_timeout_ms:1_000 ()));
  Alcotest.(check bool) "zero request timeout is rejected" true
    (Result.is_error
       (Extension_runtime.make_limits ~max_message_bytes:1024
          ~request_timeout_ms:0 ~shutdown_timeout_ms:1_000 ()))

let with_temp_workspace operation =
  let root = Filename.temp_file "monika-extension-failure-" "" in
  Sys.remove root;
  Unix.mkdir root 0o700;
  let docs = Filename.concat root "docs" in
  Unix.mkdir docs 0o700;
  let note = Filename.concat docs "note.md" in
  let output = open_out_bin note in
  output_string output "# Note\n";
  close_out output;
  Fun.protect
    ~finally:(fun () ->
      Sys.remove note;
      Unix.rmdir docs;
      Unix.rmdir root)
    (fun () -> operation root)

let test_interpret_failure_result peer () =
  with_temp_workspace (fun workspace ->
      let observation =
        Workspace_path.of_canonical_string "docs/note.md" |> Result.get_ok
      in
      let result =
        Workspace_inspect.inspect_with_extension ~workspace ~observation
          ~manifest:(manifest ()) ~executable:peer
          ~arguments:[ "interpret-failure" ]
      in
      Alcotest.(check string) "status" "diagnostics-found"
        (Command_result.status result |> Command_result.status_string);
      Alcotest.(check string) "exit class" "diagnostic-error"
        (Command_result.exit_class result |> Command_result.exit_class_string);
      match Command_result.diagnostics result with
      | [ diagnostic ] ->
          Alcotest.(check string) "diagnostic code" "extension-failure"
            (Diagnostic.code diagnostic |> Diagnostic.code_string);
          let failure =
            Diagnostic.extension_failure diagnostic |> Option.get
          in
          Alcotest.(check string) "operation" "interpret-observation"
            (Extension_failure.operation failure
            |> Extension_failure.operation_string);
          Alcotest.(check string) "failure code" "parser-unavailable"
            (Extension_failure.code failure);
          Alcotest.(check string) "failure data" {|{"retryable":true}|}
            (Extension_failure.data failure
            |> Option.get |> Yojson.Safe.to_string)
      | _ -> Alcotest.fail "expected one structured extension failure")

let cross_manifest ~name ~media_type ~path_glob ~selector_schema =
  Extension_manifest.of_yojson
    (`Assoc
      [
        ("protocolVersion", `String "1");
        ( "capability",
          `Assoc
            [
              ("type", `String "interpreter");
              ("name", `String name);
              ("version", `String "1");
              ( "appliesTo",
                `Assoc
                  [
                    ("mediaTypes", `List [ `String media_type ]);
                    ("pathGlobs", `List [ `String path_glob ]);
                  ] );
              ( "schemas",
                `Assoc [ ("selector", `String selector_schema) ] );
            ] );
      ])
  |> Result.get_ok

let cross_reference_manifest =
  Extension_manifest.of_yojson
    (`Assoc
      [
        ("protocolVersion", `String "1");
        ( "capability",
          `Assoc
            [
              ("type", `String "reference-extractor");
              ("name", `String "cross-source-references");
              ("version", `String "1");
              ( "appliesTo",
                `Assoc
                  [
                    ( "mediaTypes",
                      `List [ `String "application/x-cross-source" ] );
                    ("pathGlobs", `List [ `String "**/*.source" ]);
                  ] );
            ] );
      ])
  |> Result.get_ok

let test_cross_interpreter_resolve peer () =
  let peer =
    if Filename.is_relative peer then Filename.concat (Sys.getcwd ()) peer
    else peer
  in
  let root = Filename.temp_file "monika-cross-interpreter-" "" in
  Sys.remove root;
  Unix.mkdir root 0o700;
  let source_file = Filename.concat root "source.source" in
  let target_file = Filename.concat root "target.target" in
  let write path content =
    let output = open_out_bin path in
    output_string output content;
    close_out output
  in
  Fun.protect
    ~finally:(fun () ->
      Sys.remove source_file;
      Sys.remove target_file;
      Unix.rmdir root)
    (fun () ->
      write source_file "source\n";
      write target_file "target\n";
      let source_manifest =
        cross_manifest ~name:"cross-source"
          ~media_type:"application/x-cross-source" ~path_glob:"**/*.source"
          ~selector_schema:
            "https://example.invalid/cross-source-selector-v1.json"
      in
      let target_manifest =
        cross_manifest ~name:"cross-target"
          ~media_type:"application/x-cross-target" ~path_glob:"**/*.target"
          ~selector_schema:
            "https://example.invalid/cross-target-selector-v1.json"
      in
      let installed manifest mode =
        Installed_extension.make ~manifest ~executable:peer ~arguments:[ mode ]
        |> Result.get_ok
      in
      let registry =
        Registry_snapshot.make
          [
            installed source_manifest "cross-source";
            installed cross_reference_manifest "cross-source-references";
            installed target_manifest "cross-target";
          ]
        |> Result.get_ok
      in
      let result =
        Workspace_resolve.resolve_reference_with_registry ~workspace:root
          ~observation:
            (Workspace_path.of_canonical_string "source.source" |> Result.get_ok)
          ~reference:"cross-target" ~observed_at:"2026-08-28T00:00:00Z"
          ~registry
      in
      Alcotest.(check string) "cross-interpreter resolve status" "ok"
        (Command_result.status result |> Command_result.status_string);
      Alcotest.(check int) "one resolution snapshot" 1
        (Command_result.snapshots result |> List.length);
      Alcotest.(check int) "interpreter and extractor capabilities are reported" 3
        (Command_result.capabilities result |> List.length);
      let graph =
        Workspace_graph.query_with_registry ~workspace:root
          ~observation:
            (Workspace_path.of_canonical_string "source.source" |> Result.get_ok)
          ~direction:Workspace_graph.Outgoing ~predicate:None ~limit:50
          ~registry
        |> function
        | Ok value -> value
        | Error (Workspace_graph.Usage message)
        | Error (Workspace_graph.Internal message) -> Alcotest.fail message
      in
      Alcotest.(check int) "graph uses both interpreters" 2
        (Workspace_graph.coverage graph).interpreted_observations;
      Alcotest.(check int) "cross-interpreter graph edge" 1
        (Workspace_graph.matches graph |> List.length);
      Alcotest.(check bool) "cross-interpreter target is resolved" true
        (Workspace_graph.matches graph
        |> List.for_all (fun edge ->
               Workspace_graph.target_resolution edge
               = Workspace_graph.Resolved));
      let source_region = Identifier.make "source" |> Result.get_ok in
      let region_graph =
        Workspace_graph.query_for_region_with_registry ~workspace:root
          ~observation:
            (Workspace_path.of_canonical_string "source.source" |> Result.get_ok)
          ~region:source_region ~scope:Workspace_graph.Exact
          ~direction:Workspace_graph.Outgoing ~predicate:None ~limit:50
          ~registry
        |> function
        | Ok value -> value
        | Error (Workspace_graph.Usage message)
        | Error (Workspace_graph.Internal message) -> Alcotest.fail message
      in
      Alcotest.(check int) "extension classifies exact region endpoint" 1
        (Workspace_graph.matches region_graph |> List.length))

let () =
  let peer = Sys.getenv "MONIKA_EXTENSION_RUNTIME_PEER" in
  Alcotest.run "extension runtime"
    [
      ( "stdio JSON-RPC",
        [
          Alcotest.test_case "initialize session" `Quick
            (test_initialize_session peer);
          Alcotest.test_case "generic call" `Quick (test_generic_call peer);
          Alcotest.test_case "checked session" `Quick
            (test_checked_session peer);
          Alcotest.test_case "host byte stream" `Quick
            (test_content_stream peer);
          Alcotest.test_case "response validation" `Quick
            (test_response_validation peer);
          Alcotest.test_case "message and time limits" `Quick
            (test_limits peer);
          Alcotest.test_case "process completion" `Quick
            (test_process_completion peer);
          Alcotest.test_case "limit validation" `Quick test_limits_validation;
          Alcotest.test_case "interpret failure result" `Quick
            (test_interpret_failure_result peer);
          Alcotest.test_case "cross-interpreter resolve" `Quick
            (test_cross_interpreter_resolve peer);
        ] );
    ]
