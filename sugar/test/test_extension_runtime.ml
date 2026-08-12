open Monika_sugar

let expect_ok = function
  | Ok value -> value
  | Error failure ->
      Alcotest.failf "unexpected runtime failure [%s]: %s"
        (Extension_runtime.failure_code failure)
        (Extension_runtime.failure_message failure)

let descriptor () =
  Extension_descriptor.of_yojson
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

let test_describe peer () =
  let described =
    run peer "good" (fun session -> Extension_runtime.describe session)
    |> expect_ok
  in
  Alcotest.(check bool) "runtime descriptor equals static descriptor" true
    (Extension_descriptor.equal described (descriptor ()));
  let mismatched =
    run peer "mismatch" (fun session -> Extension_runtime.describe session)
    |> expect_ok
  in
  Alcotest.(check bool) "different capability is not equal" false
    (Extension_descriptor.equal mismatched (descriptor ()))

let test_generic_call peer () =
  let params = `Assoc [ ("enabled", `Bool true); ("count", `Int 3) ] in
  let result =
    run peer "echo" (fun session ->
        match Extension_runtime.describe session with
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
  |> expect_failure_code "describe-required";
  run peer "good" (fun session ->
      match Extension_runtime.describe session with
      | Error _ as error -> error
      | Ok _ ->
      Extension_runtime.call session ~method_name:"other.echo" ~params)
  |> expect_failure_code "invalid-request";
  run peer "good" (fun session ->
      match Extension_runtime.describe session with
      | Error _ as error -> error
      | Ok _ ->
          Extension_runtime.call session ~method_name:"monika.echo"
            ~params:(`Float 1.5))
  |> expect_failure_code "invalid-request";
  let rec nested depth =
    if depth = 0 then `Null else `List [ nested (depth - 1) ]
  in
  run peer "good" (fun session ->
      match Extension_runtime.describe session with
      | Error _ as error -> error
      | Ok _ ->
          Extension_runtime.call session ~method_name:"monika.echo"
            ~params:(nested 129))
  |> expect_failure_code "invalid-request"

let test_checked_session peer () =
  Extension_runtime.with_checked_session ~executable:peer ~arguments:[ "good" ]
    ~limits:(limits ()) ~descriptor:(descriptor ()) (fun _ -> Ok ())
  |> expect_ok;
  Extension_runtime.with_checked_session ~executable:peer
    ~arguments:[ "mismatch" ] ~limits:(limits ()) ~descriptor:(descriptor ())
    (fun _ -> Ok ())
  |> expect_failure_code "descriptor-mismatch"

let test_response_validation peer () =
  run peer "wrong-id" (fun session -> Extension_runtime.describe session)
  |> expect_failure_code "invalid-response";
  run peer "invalid-json" (fun session -> Extension_runtime.describe session)
  |> expect_failure_code "invalid-response";
  run peer "duplicate-field" (fun session -> Extension_runtime.describe session)
  |> expect_failure_code "invalid-response";
  run peer "remote-error" (fun session -> Extension_runtime.describe session)
  |> expect_failure_code "remote-error";
  run peer "remote-error-null" (fun session ->
      Extension_runtime.describe session)
  |> expect_failure_code "remote-error"

let test_limits peer () =
  run peer "oversized"
    ~limits:(limits ~max_message_bytes:512 ())
    (fun session -> Extension_runtime.describe session)
  |> expect_failure_code "response-too-large";
  run peer "timeout"
    ~limits:(limits ~request_timeout_ms:50 ())
    (fun session -> Extension_runtime.describe session)
  |> expect_failure_code "timeout";
  run peer "low-message-limit" (fun session ->
      match Extension_runtime.describe session with
      | Error _ as error -> error
      | Ok _ ->
          Extension_runtime.call session ~method_name:"monika.echo"
            ~params:(`String (String.make 600 'x')))
  |> expect_failure_code "request-too-large"

let test_process_completion peer () =
  run peer "nonzero-after-response" (fun session ->
      Extension_runtime.describe session)
  |> expect_failure_code "process-exit";
  run peer "no-exit-after-eof"
    ~limits:(limits ~shutdown_timeout_ms:50 ())
    (fun session -> Extension_runtime.describe session)
  |> expect_failure_code "shutdown-timeout"

let test_limits_validation () =
  Alcotest.(check bool) "zero message limit is rejected" true
    (Result.is_error
       (Extension_runtime.make_limits ~max_message_bytes:0
          ~request_timeout_ms:1_000 ~shutdown_timeout_ms:1_000 ()));
  Alcotest.(check bool) "zero request timeout is rejected" true
    (Result.is_error
       (Extension_runtime.make_limits ~max_message_bytes:1024
          ~request_timeout_ms:0 ~shutdown_timeout_ms:1_000 ()))

let () =
  let peer = Sys.getenv "MONIKA_EXTENSION_RUNTIME_PEER" in
  Alcotest.run "extension runtime"
    [
      ( "stdio JSON-RPC",
        [
          Alcotest.test_case "describe" `Quick (test_describe peer);
          Alcotest.test_case "generic call" `Quick (test_generic_call peer);
          Alcotest.test_case "checked session" `Quick
            (test_checked_session peer);
          Alcotest.test_case "response validation" `Quick
            (test_response_validation peer);
          Alcotest.test_case "message and time limits" `Quick
            (test_limits peer);
          Alcotest.test_case "process completion" `Quick
            (test_process_completion peer);
          Alcotest.test_case "limit validation" `Quick test_limits_validation;
        ] );
    ]
