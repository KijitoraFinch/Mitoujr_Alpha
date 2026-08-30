let capability =
  {|{"type":"interpreter","name":"custom-markdown","version":"1","acceptedObservationTypes":[{"name":"text/markdown","version":"1"}],"applicability":{"pathGlobs":["docs/*.md"]},"selectorSchemas":["https://example.invalid/schemas/custom-markdown-selector-v1.json"],"resultSchemas":["https://monika.local/schemas/interpretation.schema.json"]}|}

let runtime_description ?(max_message_bytes = 16 * 1024 * 1024) capability =
  Printf.sprintf
    {|{"protocolVersion":"1","capability":%s,"maxMessageBytes":%d,"maxContentBytes":268435456}|}
    capability max_message_bytes

let source_capability =
  {|{"type":"interpreter","name":"cross-source","version":"1","acceptedObservationTypes":[{"name":"application/x-cross-source","version":"1"}],"applicability":{"pathGlobs":["**/*.source"]},"selectorSchemas":["https://example.invalid/cross-source-selector-v1.json"],"resultSchemas":["https://monika.local/schemas/interpretation.schema.json"]}|}

let source_reference_capability =
  {|{"type":"reference-extractor","name":"cross-source-references","version":"1","acceptedObservationTypes":[{"name":"application/x-cross-source","version":"1"}],"applicability":{"pathGlobs":["**/*.source"]},"selectorSchemas":[],"resultSchemas":["https://monika.local/schemas/reference-extraction.schema.json"]}|}

let raw_reference_capability =
  {|{"type":"reference-extractor","name":"raw-references","version":"1","acceptedObservationTypes":[{"name":"application/octet-stream","version":"1"}],"applicability":{"pathGlobs":["data/*.bin"]},"selectorSchemas":[],"resultSchemas":["https://monika.local/schemas/reference-extraction.schema.json"]}|}

let target_capability =
  {|{"type":"interpreter","name":"cross-target","version":"1","acceptedObservationTypes":[{"name":"application/x-cross-target","version":"1"}],"applicability":{"pathGlobs":["**/*.target"]},"selectorSchemas":["https://example.invalid/cross-target-selector-v1.json"],"resultSchemas":["https://monika.local/schemas/interpretation.schema.json"]}|}

let resource_observer_capability =
  {|{"type":"resource-observer","name":"fixture-observer","version":"1","acceptedObservationTypes":[{"name":"application/x-fixture-bytes","version":"1"}],"applicability":{"pathGlobs":[]},"selectorSchemas":[],"resultSchemas":["https://monika.local/schemas/observation.schema.json"]}|}

let structured_interpreter_capability =
  {|{"type":"interpreter","name":"structured-fixture","version":"1","acceptedObservationTypes":[{"name":"application/vnd.fixture+json","version":"1"}],"applicability":{"pathGlobs":[]},"selectorSchemas":[],"resultSchemas":["https://monika.local/schemas/interpretation.schema.json"]}|}

let response ?(id = 1) result =
  Printf.sprintf {|{"jsonrpc":"2.0","id":%d,"result":%s}|} id result

let verify_initialize_session_request line =
  match Yojson.Safe.from_string line with
  | `Assoc fields ->
      List.assoc_opt "jsonrpc" fields = Some (`String "2.0")
      && List.assoc_opt "id" fields = Some (`Int 1)
      && List.assoc_opt "method" fields
         = Some (`String "monika.initializeSession")
      && (match List.assoc_opt "params" fields with
         | Some (`Assoc params) ->
             List.assoc_opt "protocolVersions" params
             = Some (`List [ `String "1" ])
             && (match List.assoc_opt "maxMessageBytes" params with
                | Some (`Int value) -> value > 0
                | _ -> false)
             && (match List.assoc_opt "maxContentBytes" params with
                | Some (`Int value) -> value > 0
                | _ -> false)
         | _ -> false)
  | _ -> false

let base64_value = function
  | 'A' .. 'Z' as value -> Char.code value - Char.code 'A'
  | 'a' .. 'z' as value -> Char.code value - Char.code 'a' + 26
  | '0' .. '9' as value -> Char.code value - Char.code '0' + 52
  | '+' -> 62
  | '/' -> 63
  | _ -> -1

let decode_base64 encoded =
  if String.length encoded mod 4 <> 0 then None
  else
    let output = Buffer.create (String.length encoded / 4 * 3) in
    let rec loop offset =
      if offset = String.length encoded then Some (Buffer.contents output)
      else
        let first = base64_value encoded.[offset] in
        let second = base64_value encoded.[offset + 1] in
        let third = encoded.[offset + 2] in
        let fourth = encoded.[offset + 3] in
        let third_value = if third = '=' then 0 else base64_value third in
        let fourth_value = if fourth = '=' then 0 else base64_value fourth in
        if
          first < 0 || second < 0 || third_value < 0 || fourth_value < 0
          || (third = '=' && fourth <> '=')
          || ((third = '=' || fourth = '=') && offset + 4 <> String.length encoded)
        then None
        else (
          Buffer.add_char output (Char.chr ((first lsl 2) lor (second lsr 4)));
          if third <> '=' then
            Buffer.add_char output
              (Char.chr (((second land 0x0f) lsl 4) lor (third_value lsr 2)));
          if fourth <> '=' then
            Buffer.add_char output
              (Char.chr (((third_value land 0x03) lsl 6) lor fourth_value));
          loop (offset + 4))
    in
    loop 0

let receive_content request =
  let open Yojson.Safe.Util in
  let request_id = request |> member "id" |> to_int in
  let expected_length =
    request |> member "params" |> member "content" |> member "byteLength"
    |> to_int
  in
  let output = Buffer.create expected_length in
  let rec loop offset chunks =
    let notification = input_line stdin |> Yojson.Safe.from_string in
    let params = notification |> member "params" in
    if params |> member "requestId" |> to_int <> request_id then exit 31;
    match notification |> member "method" |> to_string with
    | "monika.contentChunk" ->
        if params |> member "offset" |> to_int <> offset then exit 32;
        let decoded =
          params |> member "base64" |> to_string |> decode_base64
          |> Option.get
        in
        Buffer.add_string output decoded;
        loop (offset + String.length decoded) (chunks + 1)
    | "monika.endContent" ->
        if params |> member "byteLength" |> to_int <> offset then exit 33;
        if offset <> expected_length then exit 34;
        (Buffer.contents output, chunks)
    | _ -> exit 35
  in
  loop 0 0

let finish exit_code =
  (try
     while true do
       ignore (input_line stdin)
     done
   with End_of_file -> ());
  exit exit_code

let () =
  let mode = if Array.length Sys.argv > 1 then Sys.argv.(1) else "good" in
  let line = input_line stdin in
  match mode with
  | "interpret-failure" ->
      if not (verify_initialize_session_request line) then exit 24;
      print_endline (response (runtime_description capability));
      flush stdout;
      let request = input_line stdin |> Yojson.Safe.from_string in
      (match request with
      | `Assoc fields
        when List.assoc_opt "method" fields
             = Some (`String "monika.interpretObservation") ->
          ignore (receive_content request);
          print_endline
            (response ~id:2
               {|{"failure":{"code":"parser-unavailable","message":"parser is unavailable","data":{"retryable":true}}}|});
          flush stdout;
          finish 0
      | _ -> exit 25)
  | "stream" ->
      if not (verify_initialize_session_request line) then exit 26;
      print_endline (response (runtime_description capability));
      flush stdout;
      let request = input_line stdin |> Yojson.Safe.from_string in
      let content, chunks = receive_content request in
      let expected =
        String.init 100_000 (fun index -> Char.chr (index mod 256))
      in
      let id = Yojson.Safe.Util.(request |> member "id" |> to_int) in
      Printf.printf
        {|{"jsonrpc":"2.0","id":%d,"result":{"byteLength":%d,"chunks":%d,"matches":%s}}|}
        id (String.length content) chunks
        (if String.equal content expected then "true" else "false");
      print_newline ();
      flush stdout;
      finish 0
  | "cross-source" ->
      if not (verify_initialize_session_request line) then exit 36;
      print_endline (response (runtime_description source_capability));
      flush stdout;
      let request = input_line stdin |> Yojson.Safe.from_string in
      let content, _ = receive_content request in
      let open Yojson.Safe.Util in
      let id = request |> member "id" |> to_int in
      let observation = request |> member "params" |> member "observation" in
      let observation_id = observation |> member "id" |> to_string in
      let fingerprint =
        observation |> member "contentIdentity" |> member "hash" |> to_string
      in
      let source_region_id =
        `Assoc
          [
            ("observation", `String observation_id);
            ("local", `String "source");
          ]
      in
      let result =
        if
          request |> member "method" |> to_string
          = "monika.classifyRegionExtents"
        then `Assoc [ ("relation", `String "equal") ]
        else
        `Assoc
          [
            ( "interpretation",
              `Assoc
                [
                  ( "interpreter",
                    `Assoc
                      [
                        ("name", `String "cross-source");
                        ("version", `String "1");
                      ] );
                  ("observation", `String observation_id);
                  ( "regions",
                    `List
                      [
                        `Assoc
                          [
                            ("id", source_region_id);
                            ( "selector",
                              `Assoc
                                [
                                  ("kind", `String "region-id");
                                  ("id", `String "source");
                                ] );
                            ( "range",
                              `Assoc
                                [
                                  ("start", `Int 0);
                                  ("end", `Int (String.length content));
                                ] );
                            ( "fingerprint",
                              `Assoc
                                [
                                  ( "schema",
                                    `String
                                      "https://monika.local/schemas/sha256-fingerprint.schema.json"
                                  );
                                  ("value", `String fingerprint);
                                ] );
                          ];
                      ] );
                ] );
          ]
      in
      `Assoc [ ("jsonrpc", `String "2.0"); ("id", `Int id); ("result", result) ]
      |> Yojson.Safe.to_string |> print_endline;
      flush stdout;
      finish 0
  | "cross-source-references" ->
      if not (verify_initialize_session_request line) then exit 41;
      print_endline (response (runtime_description source_reference_capability));
      flush stdout;
      let request = input_line stdin |> Yojson.Safe.from_string in
      let content, _ = receive_content request in
      let open Yojson.Safe.Util in
      if request |> member "method" |> to_string <> "monika.extractReferences"
      then exit 42;
      let id = request |> member "id" |> to_int in
      let observation = request |> member "params" |> member "observation" in
      let observation_id = observation |> member "id" |> to_string in
      let reference_id =
        `Assoc
          [
            ( "scope",
              `Assoc
                [
                  ("kind", `String "workspace");
                  ("path", `String "source.source");
                ] );
            ("local", `String "cross-target");
          ]
      in
      let reference =
        `Assoc
          [
            ("id", reference_id);
            ( "target",
              `Assoc
                [
                  ( "origin",
                    `Assoc
                      [
                        ("kind", `String "workspace");
                        ("path", `String "target.target");
                      ] );
                  ( "selector",
                    `Assoc
                      [
                        ("kind", `String "extension");
                        ( "schema",
                          `String
                            "https://example.invalid/cross-target-selector-v1.json"
                        );
                        ("value", `Assoc [ ("kind", `String "document") ]);
                      ] );
                  ("interpreter", `String "cross-target");
                  ("interpreterVersion", `String "1");
                ] );
            ("binding", `String "tracking");
            ("expectations", `List []);
          ]
      in
      let definition =
        `Assoc
          [
            ("reference", reference);
            ( "source",
              `Assoc
                [
                  ("kind", `String "observation");
                  ("observation", `String observation_id);
                  ( "locator",
                    `Assoc
                      [
                        ("kind", `String "byte-range");
                        ( "range",
                          `Assoc
                            [
                              ("start", `Int 0);
                              ("end", `Int (String.length content));
                            ] );
                      ] );
                  ( "encoding",
                    `Assoc
                      [
                        ("name", `String "cross-source-reference");
                        ("version", `String "1");
                      ] );
                ] );
          ]
      in
      let use =
        `Assoc
          [
            ("sourceObservation", `String observation_id);
            ( "sourceRegion",
              `Assoc
                [
                  ("kind", `String "region");
                  ( "id",
                    `Assoc
                      [
                        ("observation", `String observation_id);
                        ("local", `String "source");
                      ] );
                ] );
            ( "sourceRange",
              `Assoc
                [
                  ("start", `Int 0);
                  ("end", `Int (String.length content));
                ] );
            ( "target",
              `Assoc
                [
                  ("kind", `String "named");
                  ("reference", reference_id);
                ] );
          ]
      in
      `Assoc
        [
          ("jsonrpc", `String "2.0");
          ("id", `Int id);
          ( "result",
            `Assoc
              [
                ( "extraction",
                  `Assoc
                    [
                      ("definitions", `List [ definition ]);
                      ("uses", `List [ use ]);
                    ] );
              ] );
        ]
      |> Yojson.Safe.to_string |> print_endline;
      flush stdout;
      finish 0
  | ("extract-without-interpretation" | "extract-invalid-region") as mode ->
      if not (verify_initialize_session_request line) then exit 61;
      print_endline (response (runtime_description raw_reference_capability));
      flush stdout;
      let request = input_line stdin |> Yojson.Safe.from_string in
      let _, _ = receive_content request in
      let open Yojson.Safe.Util in
      if request |> member "method" |> to_string <> "monika.extractReferences"
      then exit 62;
      let params = request |> member "params" in
      (match params with
      | `Assoc fields when not (List.mem_assoc "interpretation" fields) -> ()
      | _ -> exit 63);
      let id = request |> member "id" |> to_int in
      let observation_id =
        params |> member "observation" |> member "id" |> to_string
      in
      let uses =
        if String.equal mode "extract-invalid-region" then
          `List
            [
              `Assoc
                [
                  ("sourceObservation", `String observation_id);
                  ( "sourceRegion",
                    `Assoc
                      [
                        ("kind", `String "region");
                        ( "id",
                          `Assoc
                            [
                              ("observation", `String observation_id);
                              ("local", `String "not-produced");
                            ] );
                      ] );
                  ( "sourceRange",
                    `Assoc [ ("start", `Int 0); ("end", `Int 1) ] );
                  ( "target",
                    `Assoc
                      [
                        ("kind", `String "direct");
                        ( "address",
                          `Assoc
                            [
                              ( "origin",
                                `Assoc
                                  [
                                    ("kind", `String "workspace");
                                    ("path", `String "data/raw.bin");
                                  ] );
                              ( "selector",
                                `Assoc
                                  [ ("kind", `String "whole-observation") ] );
                            ] );
                      ] );
                ];
            ]
        else `List []
      in
      `Assoc
        [
          ("jsonrpc", `String "2.0");
          ("id", `Int id);
          ( "result",
            `Assoc
              [
                ( "extraction",
                  `Assoc [ ("definitions", `List []); ("uses", uses) ] );
              ] );
        ]
      |> Yojson.Safe.to_string |> print_endline;
      flush stdout;
      finish 0
  | "cross-target" ->
      if not (verify_initialize_session_request line) then exit 37;
      print_endline (response (runtime_description target_capability));
      flush stdout;
      let request = input_line stdin |> Yojson.Safe.from_string in
      let content, _ = receive_content request in
      let open Yojson.Safe.Util in
      let id = request |> member "id" |> to_int in
      let params = request |> member "params" in
      let observation = params |> member "observation" in
      let observation_id = observation |> member "id" |> to_string in
      let fingerprint =
        observation |> member "contentIdentity" |> member "hash" |> to_string
      in
      let selector =
        if request |> member "method" |> to_string = "monika.resolveRegion" then
          params |> member "selector"
        else
          `Assoc
            [
              ("kind", `String "extension");
              ( "schema",
                `String
                  "https://example.invalid/cross-target-selector-v1.json" );
              ("value", `Assoc [ ("kind", `String "document") ]);
            ]
      in
      let region =
        `Assoc
          [
            ( "id",
              `Assoc
                [
                  ("observation", `String observation_id);
                  ("local", `String "document");
                ] );
            ("selector", selector);
            ("summary", `String "cross-interpreter target");
            ( "range",
              `Assoc
                [
                  ("start", `Int 0);
                  ("end", `Int (String.length content));
                ] );
            ( "fingerprint",
              `Assoc
                [
                  ( "schema",
                    `String
                      "https://monika.local/schemas/sha256-fingerprint.schema.json"
                  );
                  ("value", `String fingerprint);
                ] );
          ]
      in
      let result =
        if request |> member "method" |> to_string = "monika.resolveRegion" then
          `Assoc [ ("region", region) ]
        else
          `Assoc
            [
              ( "interpretation",
                `Assoc
                  [
                    ( "interpreter",
                      `Assoc
                        [
                          ("name", `String "cross-target");
                          ("version", `String "1");
                        ] );
                    ("observation", `String observation_id);
                    ("regions", `List [ region ]);
                  ] );
            ]
      in
      `Assoc
        [
          ("jsonrpc", `String "2.0");
          ("id", `Int id);
          ("result", result);
        ]
      |> Yojson.Safe.to_string |> print_endline;
      flush stdout;
      finish 0
  | "output-stream" ->
      if not (verify_initialize_session_request line) then exit 44;
      print_endline (response (runtime_description capability));
      flush stdout;
      let request = input_line stdin |> Yojson.Safe.from_string in
      let id = Yojson.Safe.Util.(request |> member "id" |> to_int) in
      Printf.printf
        {|{"jsonrpc":"2.0","method":"monika.outputContentChunk","params":{"requestId":%d,"offset":0,"base64":"b2JzZXJ2ZWQ="}}|}
        id;
      print_newline ();
      Printf.printf
        {|{"jsonrpc":"2.0","method":"monika.endOutputContent","params":{"requestId":%d,"byteLength":8}}|}
        id;
      print_newline ();
      print_endline (response ~id {|{"accepted":true}|});
      flush stdout;
      finish 0
  | ("output-invalid-offset" | "output-no-terminator" | "output-too-large")
    as invalid_output_mode ->
      if not (verify_initialize_session_request line) then exit 51;
      print_endline (response (runtime_description capability));
      flush stdout;
      let request = input_line stdin |> Yojson.Safe.from_string in
      let id = Yojson.Safe.Util.(request |> member "id" |> to_int) in
      let offset =
        if String.equal invalid_output_mode "output-invalid-offset" then 1
        else 0
      in
      Printf.printf
        {|{"jsonrpc":"2.0","method":"monika.outputContentChunk","params":{"requestId":%d,"offset":%d,"base64":"b2JzZXJ2ZWQ="}}|}
        id offset;
      print_newline ();
      if not (String.equal invalid_output_mode "output-no-terminator") then (
        Printf.printf
          {|{"jsonrpc":"2.0","method":"monika.endOutputContent","params":{"requestId":%d,"byteLength":8}}|}
          id;
        print_newline ());
      print_endline (response ~id {|{"accepted":true}|});
      flush stdout;
      finish 0
  | "resource-observer" ->
      if not (verify_initialize_session_request line) then exit 45;
      print_endline
        (response (runtime_description resource_observer_capability));
      flush stdout;
      let request = input_line stdin |> Yojson.Safe.from_string in
      let open Yojson.Safe.Util in
      if request |> member "method" |> to_string <> "monika.observeResource"
      then exit 46;
      let id = request |> member "id" |> to_int in
      let origin = request |> member "params" |> member "origin" in
      Printf.printf
        {|{"jsonrpc":"2.0","method":"monika.outputContentChunk","params":{"requestId":%d,"offset":0,"base64":"b2JzZXJ2ZWQ="}}|}
        id;
      print_newline ();
      Printf.printf
        {|{"jsonrpc":"2.0","method":"monika.endOutputContent","params":{"requestId":%d,"byteLength":8}}|}
        id;
      print_newline ();
      let observation =
        `Assoc
          [
            ("id", `String "observation:fixture:a");
            ("origin", origin);
            ( "identity",
              `Assoc
                [
                  ( "observationType",
                    `Assoc
                      [
                        ("name", `String "application/x-fixture-bytes");
                        ("version", `String "1");
                      ] );
                  ("key", `String "fixture:a:604cee80");
                ] );
            ("representation", `Assoc [ ("kind", `String "bytes") ]);
            ( "contentIdentity",
              `Assoc
                [
                  ( "hash",
                    `String
                      "sha256:604cee807f644af47487bf2bbab442b94212ac5119f36f995f78e9e4694dae8c"
                  );
                  ("size", `Int 8);
                ] );
          ]
      in
      `Assoc
        [
          ("jsonrpc", `String "2.0");
          ("id", `Int id);
          ("result", `Assoc [ ("observation", observation) ]);
        ]
      |> Yojson.Safe.to_string |> print_endline;
      flush stdout;
      finish 0
  | "structured-interpreter" ->
      if not (verify_initialize_session_request line) then exit 47;
      print_endline
        (response (runtime_description structured_interpreter_capability));
      flush stdout;
      let request = input_line stdin |> Yojson.Safe.from_string in
      let open Yojson.Safe.Util in
      if request |> member "method" |> to_string
         <> "monika.interpretObservation"
      then exit 48;
      let params = request |> member "params" in
      if params |> member "content" <> `Null then exit 49;
      let observation = params |> member "observation" in
      if
        observation |> member "representation" |> member "kind" |> to_string
        <> "structured"
      then exit 50;
      let id = request |> member "id" |> to_int in
      let observation_id = observation |> member "id" |> to_string in
      let result =
        `Assoc
          [
            ( "interpretation",
              `Assoc
                [
                  ( "interpreter",
                    `Assoc
                      [
                        ("name", `String "structured-fixture");
                        ("version", `String "1");
                      ] );
                  ("observation", `String observation_id);
                  ("regions", `List []);
                ] );
          ]
      in
      `Assoc
        [
          ("jsonrpc", `String "2.0");
          ("id", `Int id);
          ("result", result);
        ]
      |> Yojson.Safe.to_string |> print_endline;
      flush stdout;
      finish 0
  | "echo" -> (
      if not (verify_initialize_session_request line) then exit 22;
      print_endline (response (runtime_description capability));
      flush stdout;
      let request = input_line stdin in
      match Yojson.Safe.from_string request with
      | `Assoc fields ->
          let id = List.assoc "id" fields in
          let params = List.assoc "params" fields in
          `Assoc
            [ ("jsonrpc", `String "2.0"); ("id", id); ("result", params) ]
          |> Yojson.Safe.to_string |> print_endline;
          flush stdout;
          finish 0
      | _ -> exit 23)
  | "good" ->
      if verify_initialize_session_request line then (
        print_endline (response (runtime_description capability));
        flush stdout;
        finish 0)
      else exit 20
  | "low-message-limit" ->
      print_endline
        (response (runtime_description ~max_message_bytes:512 capability));
      flush stdout;
      finish 0
  | "mismatch" ->
      let other_capability =
        {|{"type":"interpreter","name":"other","version":"1","acceptedObservationTypes":[{"name":"text/markdown","version":"1"}],"applicability":{"pathGlobs":["docs/*.md"]},"selectorSchemas":["https://example.invalid/schemas/custom-markdown-selector-v1.json"],"resultSchemas":["https://monika.local/schemas/interpretation.schema.json"]}|}
      in
      print_endline (response (runtime_description other_capability));
      flush stdout;
      finish 0
  | "wrong-id" ->
      print_endline (response ~id:2 (runtime_description capability));
      flush stdout;
      finish 0
  | "remote-error" ->
      print_endline
        {|{"jsonrpc":"2.0","id":1,"error":{"code":-32001,"message":"cannot initialize session","data":{"retryable":false}}}|};
      flush stdout;
      finish 0
  | "remote-error-null" ->
      print_endline
        {|{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"parse error"}}|};
      flush stdout;
      finish 0
  | "invalid-json" ->
      print_endline "{not-json";
      flush stdout;
      finish 0
  | "duplicate-field" ->
      Printf.printf
        "%s\n"
        (Printf.sprintf
           {|{"jsonrpc":"2.0","id":1,"id":1,"result":%s}|}
           (runtime_description capability));
      flush stdout;
      finish 0
  | "oversized" ->
      print_endline (String.make 4096 'x');
      flush stdout;
      finish 0
  | "timeout" ->
      Unix.sleepf 0.25;
      print_endline (response (runtime_description capability));
      flush stdout;
      finish 0
  | "nonzero-after-response" ->
      print_endline (response (runtime_description capability));
      flush stdout;
      finish 7
  | "no-exit-after-eof" ->
      print_endline (response (runtime_description capability));
      flush stdout;
      (try ignore (input_line stdin) with End_of_file -> ());
      Unix.sleepf 5.0
  | _ -> exit 21
