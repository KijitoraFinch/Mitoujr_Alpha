let capability =
  {|{"type":"interpreter","name":"custom-markdown","version":"1","appliesTo":{"mediaTypes":["text/markdown"],"pathGlobs":["docs/*.md"]},"schemas":{"selector":"https://example.invalid/schemas/custom-markdown-selector-v1.json"}}|}

let runtime_description ?(max_message_bytes = 16 * 1024 * 1024) capability =
  Printf.sprintf
    {|{"protocolVersion":"1","capability":%s,"maxMessageBytes":%d}|}
    capability max_message_bytes

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
         | _ -> false)
  | _ -> false

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
        {|{"type":"interpreter","name":"other","version":"1"}|}
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
        {|{"jsonrpc":"2.0","id":1,"error":{"code":-32001,"message":"cannot initialize session"}}|};
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
