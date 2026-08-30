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
                    ("pathGlobs", `List [ `String "docs/*.md" ]);
                  ] );
              ( "selectorSchemas",
                `List
                  [
                    `String
                      "https://example.invalid/schemas/custom-markdown-selector-v1.json";
                  ] );
              ( "resultSchemas",
                `List
                  [
                    `String
                      "https://monika.local/schemas/interpretation.schema.json";
                  ] );
            ] );
      ])
  |> Result.get_ok

let resource_observer_manifest () =
  Extension_manifest.of_yojson
    (`Assoc
      [
        ("protocolVersion", `String "1");
        ( "capability",
          `Assoc
            [
              ("type", `String "resource-observer");
              ("name", `String "fixture-observer");
              ("version", `String "1");
              ( "acceptedObservationTypes",
                `List
                  [
                    `Assoc
                      [
                        ("name", `String "application/x-fixture-bytes");
                        ("version", `String "1");
                      ];
                  ] );
              ("applicability", `Assoc [ ("pathGlobs", `List []) ]);
              ("selectorSchemas", `List []);
              ( "resultSchemas",
                `List
                  [
                    `String
                      "https://monika.local/schemas/observation.schema.json";
                  ] );
            ] );
      ])
  |> Result.get_ok

let fixture_bytes_interpreter_manifest () =
  Extension_manifest.of_yojson
    (`Assoc
      [
        ("protocolVersion", `String "1");
        ( "capability",
          `Assoc
            [
              ("type", `String "interpreter");
              ("name", `String "fixture-bytes");
              ("version", `String "1");
              ( "acceptedObservationTypes",
                `List
                  [
                    `Assoc
                      [
                        ("name", `String "application/x-fixture-bytes");
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
      ])
  |> Result.get_ok

let structured_interpreter_manifest () =
  Extension_manifest.of_yojson
    (`Assoc
      [
        ("protocolVersion", `String "1");
        ( "capability",
          `Assoc
            [
              ("type", `String "interpreter");
              ("name", `String "structured-fixture");
              ("version", `String "1");
              ( "acceptedObservationTypes",
                `List
                  [
                    `Assoc
                      [
                        ("name", `String "application/vnd.fixture+json");
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
      ])
  |> Result.get_ok

let raw_reference_extractor_manifest () =
  Extension_manifest.of_yojson
    (`Assoc
      [
        ("protocolVersion", `String "1");
        ( "capability",
          `Assoc
            [
              ("type", `String "reference-extractor");
              ("name", `String "raw-references");
              ("version", `String "1");
              ( "acceptedObservationTypes",
                `List
                  [
                    `Assoc
                      [
                        ("name", `String "application/octet-stream");
                        ("version", `String "1");
                      ];
                  ] );
              ( "applicability",
                `Assoc [ ("pathGlobs", `List [ `String "data/*.bin" ]) ] );
              ("selectorSchemas", `List []);
              ( "resultSchemas",
                `List
                  [
                    `String
                      "https://monika.local/schemas/reference-extraction.schema.json";
                  ] );
            ] );
      ])
  |> Result.get_ok

let simple_conformance_manifest ~kind ~name ~observation_types ~result_schema =
  let observation_types =
    List.map
      (fun (name, version) ->
        `Assoc
          [ ("name", `String name); ("version", `String version) ])
      observation_types
  in
  Extension_manifest.of_yojson
    (`Assoc
      [
        ("protocolVersion", `String "1");
        ( "capability",
          `Assoc
            [
              ("type", `String kind);
              ("name", `String name);
              ("version", `String "1");
              ("acceptedObservationTypes", `List observation_types);
              ("applicability", `Assoc [ ("pathGlobs", `List []) ]);
              ("selectorSchemas", `List []);
              ("resultSchemas", `List [ `String result_schema ]);
            ] );
      ])
  |> Result.get_ok

let limits ?(max_message_bytes = 16 * 1024 * 1024)
    ?(max_content_bytes = 256 * 1024 * 1024)
    ?(request_timeout_ms = 1_000) ?(shutdown_timeout_ms = 1_000) () =
  Extension_runtime.make_limits ~max_message_bytes ~max_content_bytes
    ~request_timeout_ms ~shutdown_timeout_ms ()
  |> Result.get_ok

let run peer mode ?(limits = limits ()) operation =
  Extension_runtime.with_session ~executable:peer ~arguments:[ mode ]
    ~authority:Extension_authority.default_sandboxed ~limits operation

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
    ~authority:Extension_authority.default_sandboxed
    ~limits:(limits ()) ~manifest:(manifest ()) (fun _ -> Ok ())
  |> expect_ok;
  Extension_runtime.with_checked_session ~executable:peer
    ~arguments:[ "mismatch" ] ~authority:Extension_authority.default_sandboxed
    ~limits:(limits ()) ~manifest:(manifest ())
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
    (result |> member "matches" |> to_bool);
  run peer "stream" ~limits:(limits ~max_content_bytes:4 ()) (fun session ->
      match Extension_runtime.initialize_session session with
      | Error _ as error -> error
      | Ok _ ->
          Extension_runtime.call_with_content session
            ~method_name:"monika.streamTest" ~params:(`Assoc [])
            ~content:"too large")
  |> expect_failure_code "content-too-large"

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

let test_output_stream peer () =
  let result, content =
    run peer "output-stream" (fun session ->
        match Extension_runtime.initialize_session session with
        | Error _ as error -> error
        | Ok _ ->
            Extension_runtime.call_receiving_content session
              ~method_name:"monika.observeResource"
              ~params:(`Assoc [ ("origin", `String "fixture") ]))
    |> expect_ok
  in
  Alcotest.(check string) "streamed bytes" "observed" (Option.get content);
  Alcotest.(check string) "response retained" {|{"accepted":true}|}
    (Yojson.Safe.to_string result)

let test_invalid_output_streams peer () =
  let call mode limits =
    run peer mode ~limits (fun session ->
        match Extension_runtime.initialize_session session with
        | Error _ as error -> error
        | Ok _ ->
            Extension_runtime.call_receiving_content session
              ~method_name:"monika.observeResource"
              ~params:(`Assoc [ ("origin", `String "fixture") ]))
  in
  call "output-invalid-offset" (limits ())
  |> expect_failure_code "invalid-response";
  call "output-no-terminator" (limits ())
  |> expect_failure_code "invalid-response";
  call "output-too-large" (limits ~max_content_bytes:4 ())
  |> expect_failure_code "content-too-large"

let test_resource_observer peer () =
  let manifest = resource_observer_manifest () in
  let peer = Unix.realpath peer in
  let extension =
    let authority =
      Extension_authority.resource_observer ~launch_paths:[]
        ~resource_read_paths:[] ~network:false
      |> Result.get_ok
    in
    Installed_extension.make ~manifest ~executable:peer
      ~arguments:[ "resource-observer" ] ~authority
    |> function Ok value -> value | Error message -> Alcotest.fail message
  in
  let registry = Registry_snapshot.make [ extension ] |> Result.get_ok in
  let observer =
    Resource_observer.make ~name:"fixture-observer" ~version:"1" ()
    |> Result.get_ok
  in
  let origin =
    Observation.extension ~observer ~locator:(`Assoc [ ("key", `String "a") ])
      ()
    |> Result.get_ok
  in
  match Resource_observer_runner.observe registry origin |> Result.get_ok with
  | Resource_observer_runner.Observed { observation; _ } ->
      Alcotest.(check (option string)) "fixed host-owned bytes" (Some "observed")
        (Observation.bytes observation);
      Alcotest.(check bool) "requested Origin retained" true
        (Origin.equal origin (Observation.origin observation))
  | Resource_observer_runner.Unsupported
  | Resource_observer_runner.Failure _ ->
      Alcotest.fail "expected a fixed Resource Observer result"

let test_sidecar_scope_observation peer () =
  let peer = Unix.realpath peer in
  let root = Filename.temp_file "monika-extension-sidecar-scope-" "" in
  Sys.remove root;
  Unix.mkdir root 0o700;
  let sidecar = Filename.concat root "remote.annotations.yaml" in
  let output = open_out_bin sidecar in
  output_string output
    {|version: 2
scope:
  origin:
    kind: extension
    observer:
      name: fixture-observer
      version: "1"
    locator:
      key: a
authored:
  refs:
    self:
      target:
        origin:
          kind: extension
          observer:
            name: fixture-observer
            version: "1"
          locator:
            key: a
        selector:
          kind: whole-observation
      binding:
        mode: floating
      expect: []
  annotations:
    self-link:
      subject:
        origin:
          kind: extension
          observer:
            name: fixture-observer
            version: "1"
          locator:
            key: a
        selector:
          kind: whole-observation
      predicate: related-to
      object:
        ref: self
    remote-link:
      subject:
        origin:
          kind: extension
          observer:
            name: fixture-observer
            version: "1"
          locator:
            key: a
        selector:
          kind: whole-observation
      predicate: follows
      object:
        region:
          origin:
            kind: extension
            observer:
              name: fixture-observer
              version: "1"
            locator:
              key: b
          selector:
            kind: whole-observation
derived:
  refs: {}
  annotations: {}
|};
  close_out output;
  Fun.protect
    ~finally:(fun () ->
      Sys.remove sidecar;
      Unix.rmdir root)
    (fun () ->
      let observer_authority =
        Extension_authority.resource_observer ~launch_paths:[]
          ~resource_read_paths:[] ~network:false
        |> Result.get_ok
      in
      let installed manifest mode authority =
        Installed_extension.make ~manifest ~executable:peer ~arguments:[ mode ]
          ~authority
        |> Result.get_ok
      in
      let registry =
        Registry_snapshot.make
          [
            installed (resource_observer_manifest ()) "resource-observer"
              observer_authority;
            installed (fixture_bytes_interpreter_manifest ())
              "fixture-bytes-interpreter"
              Extension_authority.default_sandboxed;
          ]
        |> Result.get_ok
      in
      let snapshot =
        Workspace_graph.build_snapshot_with_registry ~workspace:root ~registry
        |> function
        | Ok snapshot -> snapshot
        | Error (Workspace_graph.Usage message)
        | Error (Workspace_graph.Internal message) -> Alcotest.fail message
      in
      let observations = Workspace_graph_snapshot.observations snapshot in
      Alcotest.(check int)
        "Sidecar scope and Annotation address drive Resource observation" 2
        (List.length observations);
      Alcotest.(check bool) "observed Resources are Extension Origins" true
        (List.for_all
           (fun observation ->
             match Observation.origin observation with
             | Origin.Extension _ -> true
             | Origin.Workspace _ | Origin.Git _ | Origin.Web _
             | Origin.Generated _ | Origin.External _ ->
                 false)
           observations);
      let coverage = Workspace_graph_snapshot.coverage snapshot in
      Alcotest.(check int) "external Origins were observed" 2
        (Coverage.observed coverage);
      Alcotest.(check int) "external Observations were interpreted" 2
        (Coverage.interpreted coverage);
      let reference_occurrences =
        match
          Workspace_graph_snapshot.reference_index snapshot
          |> Reference_index.entries
        with
        | [ (_, Reference_index.Consistent { occurrences; _ }) ] ->
            Nonempty.length occurrences
        | _ -> Alcotest.fail "expected one consistent Sidecar reference"
      in
      Alcotest.(check int) "Sidecar reference is indexed exactly once" 1
        reference_occurrences;
      let annotation_occurrences =
        Workspace_graph_snapshot.annotation_index snapshot
        |> Annotation_index.entries
      in
      Alcotest.(check int) "both Sidecar annotations are indexed" 2
        (List.length annotation_occurrences);
      Alcotest.(check bool) "Sidecar annotations are each indexed exactly once"
        true
        (List.for_all
           (function
             | _, Annotation_index.Consistent { occurrences; _ } ->
                 Nonempty.length occurrences = 1
             | _, Annotation_index.Conflict _ -> false)
           annotation_occurrences);
      Alcotest.(check bool) "external scope graph is complete" true
        (Coverage.complete coverage))

let test_structured_observation_transfer peer () =
  let manifest = structured_interpreter_manifest () in
  let extension =
    Installed_extension.make ~manifest ~executable:(Unix.realpath peer)
      ~arguments:[ "structured-interpreter" ]
      ~authority:Extension_authority.default_sandboxed
    |> Result.get_ok
  in
  let origin = Observation.external_ "fixture:structured" |> Result.get_ok in
  let observation_type =
    Observation_type.make ~name:"application/vnd.fixture+json" ~version:"1" ()
    |> Result.get_ok
  in
  let identity =
    Observation_identity.make ~observation_type ~key:"fixture:structured:1" ()
    |> Result.get_ok
  in
  let observation =
    Observation.of_structured
      ~id:(Observation_id.make "observation:fixture:structured" |> Result.get_ok)
      ~origin ~identity ~schema:"https://example.invalid/fixture.schema.json"
      ~value:(`Assoc [ ("value", `Int 42) ]) ()
    |> Result.get_ok
  in
  let inspection =
    Workspace_inspect.inspect_fixed_observation_with_registry ~observation
      ~sidecar_snapshots:[] ~base_diagnostics:[]
      ~registry:(Registry_snapshot.make [ extension ] |> Result.get_ok)
    |> function
    | Ok inspection -> inspection
    | Error Workspace_inspect.Observation_changed ->
        Alcotest.fail "structured Observation unexpectedly changed"
    | Error (Workspace_inspect.Invalid_observation message) ->
        Alcotest.fail message
  in
  Alcotest.(check bool) "structured interpretation succeeds" true
    (Option.is_some inspection.interpretation);
  Alcotest.(check (option string)) "no byte stream is synthesized" None
    inspection.content;
  Alcotest.(check int) "structured Observation is covered" 1
    (Command_result.coverage inspection.result |> Coverage.interpreted)

let inspect_raw_with_extractor peer mode =
  let manifest = raw_reference_extractor_manifest () in
  let extension =
    Installed_extension.make ~manifest ~executable:(Unix.realpath peer)
      ~arguments:[ mode ]
      ~authority:Extension_authority.default_sandboxed
    |> Result.get_ok
  in
  let path = Workspace_path.of_canonical_string "data/raw.bin" |> Result.get_ok in
  let observation =
    Observation.of_bytes
      ~id:(Observation_id.make "observation:data/raw.bin" |> Result.get_ok)
      ~origin:(Observation.workspace path)
      ~observation_type:Observation_type.binary ~bytes:"raw\000bytes"
  in
  Workspace_inspect.inspect_fixed_observation_with_registry ~observation
    ~sidecar_snapshots:[] ~base_diagnostics:[]
    ~registry:(Registry_snapshot.make [ extension ] |> Result.get_ok)
  |> function
  | Ok inspection -> inspection
  | Error Workspace_inspect.Observation_changed ->
      Alcotest.fail "fixed raw Observation unexpectedly changed"
  | Error (Workspace_inspect.Invalid_observation message) ->
      Alcotest.fail message

let test_extractor_without_interpretation peer () =
  let inspection =
    inspect_raw_with_extractor peer "extract-without-interpretation"
  in
  Alcotest.(check bool) "no Interpretation is synthesized" true
    (Option.is_none inspection.interpretation);
  Alcotest.(check int) "applicable extractor still runs" 1
    (Command_result.capabilities inspection.result |> List.length);
  Alcotest.(check (list string)) "unsupported interpretation remains explicit"
    [ "unsupported-observation" ]
    (Command_result.diagnostics inspection.result
    |> List.map (fun diagnostic ->
           Diagnostic.code diagnostic |> Diagnostic.code_string))

let test_invalid_extractor_region peer () =
  let inspection = inspect_raw_with_extractor peer "extract-invalid-region" in
  Alcotest.(check (list string)) "invalid Region is diagnosed and discarded"
    [ "extension-failure"; "unsupported-observation" ]
    (Command_result.diagnostics inspection.result
    |> List.map (fun diagnostic ->
           Diagnostic.code diagnostic |> Diagnostic.code_string));
  let failure =
    Command_result.diagnostics inspection.result
    |> List.find_map Diagnostic.extension_failure |> Option.get
  in
  Alcotest.(check string) "boundary failure code" "invalid-result"
    (Extension_failure.code failure);
  Alcotest.(check string) "boundary failure operation" "extract-references"
    (Extension_failure.operation failure |> Extension_failure.operation_string);
  Alcotest.(check int) "invalid reference use is not admitted" 0
    (Command_result.reference_uses inspection.result |> List.length)

let sandbox_probe peer ~mode ~manifest ~authority_for_secret operation =
  let secret = Filename.temp_file "monika-extension-secret-" "" in
  let outside_write = Filename.temp_file "monika-extension-write-" "" in
  Sys.remove outside_write;
  let output = open_out_bin secret in
  output_string output "host-only";
  close_out output;
  let listener = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt listener Unix.SO_REUSEADDR true;
  Unix.bind listener (Unix.ADDR_INET (Unix.inet_addr_loopback, 0));
  Unix.listen listener 1;
  let port =
    match Unix.getsockname listener with
    | Unix.ADDR_INET (_, port) -> string_of_int port
    | Unix.ADDR_UNIX _ -> Alcotest.fail "loopback listener is not an INET socket"
  in
  Unix.putenv "MONIKA_PARENT_SECRET" "must-not-be-inherited";
  Fun.protect
    ~finally:(fun () ->
      if Sys.file_exists secret then Sys.remove secret;
      if Sys.file_exists outside_write then Sys.remove outside_write;
      Unix.close listener)
    (fun () ->
      let authority = authority_for_secret secret in
      Extension_runtime.with_checked_session ~executable:peer
        ~arguments:[ mode; secret; outside_write; port ] ~authority
        ~limits:(limits ()) ~manifest
        (fun session ->
          Extension_runtime.call session ~method_name:"monika.probe"
            ~params:(`Assoc []))
      |> expect_ok
      |> function
      | `Assoc fields -> operation fields
      | _ -> Alcotest.fail "sandbox probe returned a non-object")

let test_sandbox_boundary peer () =
  sandbox_probe peer ~mode:"sandbox-probe" ~manifest:(manifest ())
    ~authority_for_secret:(fun _ -> Extension_authority.default_sandboxed)
    (fun fields ->
      let checks =
        [
            "cwdIsScratch";
            "parentEnvironmentHidden";
            "outsideReadDenied";
            "outsideMetadataDenied";
            "outsideWriteDenied";
            "networkDenied";
            "scratchWriteAllowed";
            "scratchLimitEnforced";
        ]
      in
      let failed =
        List.filter
          (fun name -> List.assoc_opt name fields <> Some (`Bool true))
          checks
      in
      Alcotest.(check (list string)) "all sandbox boundaries" [] failed)

let test_resource_observer_authority peer () =
  sandbox_probe peer ~mode:"observer-sandbox-probe"
    ~manifest:(resource_observer_manifest ())
    ~authority_for_secret:(fun secret ->
      Extension_authority.resource_observer ~launch_paths:[]
        ~resource_read_paths:[ secret ] ~network:true
      |> Result.get_ok)
    (fun fields ->
      let expected =
        [
          ("cwdIsScratch", true);
          ("parentEnvironmentHidden", true);
          ("outsideReadDenied", false);
          ("outsideMetadataDenied", false);
          ("outsideWriteDenied", true);
          ("networkDenied", false);
          ("scratchWriteAllowed", true);
          ("scratchLimitEnforced", true);
        ]
      in
      let failed =
        List.filter
          (fun (name, expected) ->
            List.assoc_opt name fields <> Some (`Bool expected))
          expected
        |> List.map fst
      in
      Alcotest.(check (list string)) "explicit observer grants" [] failed);
  let invalid_authority =
    Extension_authority.resource_observer ~launch_paths:[]
      ~resource_read_paths:[] ~network:false
    |> Result.get_ok
  in
  Extension_runtime.with_checked_session ~executable:peer ~arguments:[ "good" ]
    ~authority:invalid_authority ~limits:(limits ()) ~manifest:(manifest ())
    (fun _ -> Ok ())
  |> expect_failure_code "invalid-authority"

let test_capability_conformance_matrix peer () =
  let annotation_manifest =
    simple_conformance_manifest ~kind:"annotation-extractor"
      ~name:"raw-annotations"
      ~observation_types:[ ("application/octet-stream", "1") ]
      ~result_schema:
        "https://monika.local/schemas/annotation-extraction.schema.json"
  in
  let auditor_manifest =
    simple_conformance_manifest ~kind:"auditor" ~name:"conformance-auditor"
      ~observation_types:[]
      ~result_schema:"https://monika.local/schemas/diagnostic.schema.json"
  in
  let deriver_manifest =
    simple_conformance_manifest ~kind:"deriver" ~name:"conformance-deriver"
      ~observation_types:[]
      ~result_schema:"https://monika.local/schemas/proposed-patch.schema.json"
  in
  let observer_authority =
    Extension_authority.resource_observer ~launch_paths:[]
      ~resource_read_paths:[] ~network:false
    |> Result.get_ok
  in
  let cases =
    [
      ( "conformance-reference",
        raw_reference_extractor_manifest (),
        Extension_authority.default_sandboxed,
        [ "monika.extractReferences" ] );
      ( "conformance-annotation",
        annotation_manifest,
        Extension_authority.default_sandboxed,
        [ "monika.extractAnnotations" ] );
      ( "conformance-auditor",
        auditor_manifest,
        Extension_authority.default_sandboxed,
        [ "monika.audit" ] );
      ( "conformance-deriver",
        deriver_manifest,
        Extension_authority.default_sandboxed,
        [ "monika.derive" ] );
      ( "conformance-observer",
        resource_observer_manifest (),
        observer_authority,
        [ "monika.observeResource" ] );
    ]
  in
  List.iter
    (fun (mode, manifest, authority, expected) ->
      let result =
        Extension_runtime.with_checked_session ~executable:peer
          ~arguments:[ mode ] ~authority ~limits:(limits ()) ~manifest
          (fun session -> Ok (Extension_conformance.check ~session ~manifest))
        |> expect_ok
      in
      match result with
      | Ok methods -> Alcotest.(check (list string)) mode expected methods
      | Error _ -> Alcotest.failf "%s conformance unexpectedly failed" mode)
    cases

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
  Extension_runtime.with_session ~executable:peer
    ~arguments:(List.init 129 (fun _ -> "argument"))
    ~authority:Extension_authority.default_sandboxed ~limits:(limits ())
    (fun _ -> Ok ())
  |> expect_failure_code "invalid-command";
  run peer "nonzero-after-response" (fun session ->
      Extension_runtime.initialize_session session)
  |> expect_failure_code "process-exit";
  run peer "no-exit-after-eof"
    ~limits:(limits ~shutdown_timeout_ms:50 ())
    (fun session -> Extension_runtime.initialize_session session)
  |> expect_failure_code "shutdown-timeout";
  run peer "good" (fun _ -> invalid_arg "host callback failed")
  |> expect_failure_code "host-operation-exception";
  let listener = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Fun.protect
    ~finally:(fun () -> Unix.close listener)
    (fun () ->
      Unix.setsockopt listener Unix.SO_REUSEADDR true;
      Unix.bind listener (Unix.ADDR_INET (Unix.inet_addr_loopback, 0));
      Unix.listen listener 1;
      let port =
        match Unix.getsockname listener with
        | Unix.ADDR_INET (_, port) -> string_of_int port
        | Unix.ADDR_UNIX _ -> Alcotest.fail "expected an INET listener"
      in
      let authority =
        Extension_authority.resource_observer ~launch_paths:[]
          ~resource_read_paths:[] ~network:true
        |> Result.get_ok
      in
      let result =
        Extension_runtime.with_session ~executable:peer
          ~arguments:[ "background-child"; port ] ~authority
          ~limits:(limits ~shutdown_timeout_ms:50 ()) (fun session ->
            match Extension_runtime.initialize_session session with
            | Error _ as error -> error
            | Ok _ ->
                Extension_runtime.call session ~method_name:"monika.spawnFixture"
                  ~params:(`Assoc []))
      in
      (match result with
      | Ok _ -> ()
      | Error failure
        when String.equal (Extension_runtime.failure_code failure)
               "shutdown-timeout" ->
          ()
      | Error failure ->
          Alcotest.failf "unexpected descendant cleanup failure [%s]: %s"
            (Extension_runtime.failure_code failure)
            (Extension_runtime.failure_message failure));
      let readable, _, _ = Unix.select [ listener ] [] [] 0.4 in
      Alcotest.(check bool) "session descendants cannot outlive the session" true
        (readable = []))

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
          ~authority:Extension_authority.default_sandboxed
      in
      Alcotest.(check string) "status" "diagnostics-found"
        (Command_result.status result |> Command_result.status_string);
      Alcotest.(check string) "exit class" "diagnostic-error"
        (Command_result.exit_class result |> Command_result.exit_class_string);
      Alcotest.(check int) "failed Observation retains its Whole Region" 1
        (Command_result.regions result |> List.length);
      let coverage = Command_result.coverage result in
      Alcotest.(check int) "failed Observation remains observed" 1
        (Coverage.observed coverage);
      Alcotest.(check int) "Interpreter failure is covered" 1
        (Coverage.failed coverage);
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
              ( "acceptedObservationTypes",
                `List
                  [
                    `Assoc
                      [
                        ("name", `String media_type);
                        ("version", `String "1");
                      ];
                  ] );
              ( "applicability",
                `Assoc
                  [
                    ("pathGlobs", `List [ `String path_glob ]);
                  ] );
              ("selectorSchemas", `List [ `String selector_schema ]);
              ( "resultSchemas",
                `List
                  [
                    `String
                      "https://monika.local/schemas/interpretation.schema.json";
                  ] );
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
              ( "acceptedObservationTypes",
                `List
                  [
                    `Assoc
                      [
                        ("name", `String "application/x-cross-source");
                        ("version", `String "1");
                      ];
                  ] );
              ( "applicability",
                `Assoc
                  [
                    ("pathGlobs", `List [ `String "**/*.source" ]);
                  ] );
              ("selectorSchemas", `List []);
              ( "resultSchemas",
                `List
                  [
                    `String
                      "https://monika.local/schemas/reference-extraction.schema.json";
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
          ~authority:Extension_authority.default_sandboxed
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
          ~previous_snapshot:None
          ~registry
      in
      Alcotest.(check string) "cross-interpreter resolve status" "ok"
        (Command_result.status result |> Command_result.status_string);
      Alcotest.(check int) "one resolution snapshot" 1
        (Command_result.snapshots result |> List.length);
      Alcotest.(check int) "one resolved target Region" 1
        (Command_result.regions result |> List.length);
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
        (Workspace_graph.coverage graph |> Coverage.interpreted);
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
  let tests =
    if String.equal (Extension_sandbox.platform ()) "windows" then
      [
        Alcotest.test_case "unsupported platform fails closed" `Quick
          (fun () ->
            Extension_runtime.with_session ~executable:peer
              ~arguments:[ "good" ]
              ~authority:Extension_authority.default_sandboxed
              ~limits:(limits ()) (fun _ -> Ok ())
            |> expect_failure_code "sandbox-setup-failed");
      ]
    else
      [
        Alcotest.test_case "initialize session" `Quick
          (test_initialize_session peer);
        Alcotest.test_case "generic call" `Quick (test_generic_call peer);
        Alcotest.test_case "checked session" `Quick
          (test_checked_session peer);
        Alcotest.test_case "host byte stream" `Quick
          (test_content_stream peer);
        Alcotest.test_case "extension byte stream" `Quick
          (test_output_stream peer);
        Alcotest.test_case "invalid extension byte streams" `Quick
          (test_invalid_output_streams peer);
        Alcotest.test_case "resource observer" `Quick
          (test_resource_observer peer);
        Alcotest.test_case "Sidecar scope Resource observation" `Quick
          (test_sidecar_scope_observation peer);
        Alcotest.test_case "structured Observation transfer" `Quick
          (test_structured_observation_transfer peer);
        Alcotest.test_case "extractor without Interpretation" `Quick
          (test_extractor_without_interpretation peer);
        Alcotest.test_case "invalid extractor Region" `Quick
          (test_invalid_extractor_region peer);
        Alcotest.test_case "sandbox authority boundary" `Quick
          (test_sandbox_boundary peer);
        Alcotest.test_case "Resource Observer authority" `Quick
          (test_resource_observer_authority peer);
        Alcotest.test_case "capability conformance matrix" `Quick
          (test_capability_conformance_matrix peer);
        Alcotest.test_case "response validation" `Quick
          (test_response_validation peer);
        Alcotest.test_case "message and time limits" `Quick (test_limits peer);
        Alcotest.test_case "process completion" `Quick
          (test_process_completion peer);
        Alcotest.test_case "limit validation" `Quick test_limits_validation;
        Alcotest.test_case "interpret failure result" `Quick
          (test_interpret_failure_result peer);
        Alcotest.test_case "cross-interpreter resolve" `Quick
          (test_cross_interpreter_resolve peer);
      ]
  in
  Alcotest.run "extension runtime"
    [ ("stdio JSON-RPC", tests) ]
