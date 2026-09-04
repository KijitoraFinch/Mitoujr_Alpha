type limits = {
  max_message_bytes : int;
  max_content_bytes : int;
  request_timeout_ms : int;
  shutdown_timeout_ms : int;
}

type failure = {
  code : string;
  message : string;
  data : Yojson.Safe.t option;
}

type session = {
  pid : int;
  from_extension : Unix.file_descr;
  to_extension : Unix.file_descr;
  limits : limits;
  mutable to_extension_open : bool;
  mutable from_extension_open : bool;
  mutable unread : string;
  mutable next_id : int;
  mutable negotiated_max_message_bytes : int;
  mutable negotiated_max_content_bytes : int;
  mutable initialized : bool;
}

external extension_child_setup : string -> int -> Unix.file_descr -> int
  = "monika_sugar_extension_child_setup"

let ( let* ) = Result.bind

let default_limits =
  {
    max_message_bytes = 16 * 1024 * 1024;
    max_content_bytes = 256 * 1024 * 1024;
    request_timeout_ms = 30_000;
    shutdown_timeout_ms = 1_000;
  }

let make_limits ~max_message_bytes ?(max_content_bytes = 256 * 1024 * 1024)
    ~request_timeout_ms ~shutdown_timeout_ms () =
  if max_message_bytes <= 0 then Error "max_message_bytes must be positive"
  else if not (Protocol_integer.is_safe max_message_bytes) then
    Error "max_message_bytes exceeds the protocol safe-integer range"
  else if max_content_bytes <= 0 then Error "max_content_bytes must be positive"
  else if not (Protocol_integer.is_safe max_content_bytes) then
    Error "max_content_bytes exceeds the protocol safe-integer range"
  else if request_timeout_ms <= 0 then
    Error "request_timeout_ms must be positive"
  else if not (Protocol_integer.is_safe request_timeout_ms) then
    Error "request_timeout_ms exceeds the protocol safe-integer range"
  else if shutdown_timeout_ms <= 0 then
    Error "shutdown_timeout_ms must be positive"
  else if not (Protocol_integer.is_safe shutdown_timeout_ms) then
    Error "shutdown_timeout_ms exceeds the protocol safe-integer range"
  else
    Ok
      {
        max_message_bytes;
        max_content_bytes;
        request_timeout_ms;
        shutdown_timeout_ms;
      }

let max_message_bytes value = value.max_message_bytes
let max_content_bytes value = value.max_content_bytes
let request_timeout_ms value = value.request_timeout_ms
let shutdown_timeout_ms value = value.shutdown_timeout_ms
let failure ?data code message = Error { code; message; data }
let failure_code value = value.code
let failure_message value = value.message
let failure_data value = value.data

let contains_nul value = String.contains value '\000'

let duplicate_name fields =
  let names = List.map fst fields |> List.sort String.compare in
  let rec loop = function
    | left :: (right :: _ as rest) ->
        String.equal left right || loop rest
    | [] | [ _ ] -> false
  in
  loop names

let maximum_json_depth = 128

let rec normalize_json_at depth path json =
  if depth > maximum_json_depth then
    Error (path ^ ": JSON nesting exceeds the protocol limit")
  else
    match json with
    | `Null -> Ok `Null
    | `Bool value -> Ok (`Bool value)
    | `String value when Utf8.is_valid value -> Ok (`String value)
    | `String _ -> Error (path ^ ": string must be valid UTF-8")
    | `Int value when Protocol_integer.is_safe value -> Ok (`Int value)
    | `Int _ -> Error (path ^ ": integer exceeds the protocol safe range")
    | `Intlit encoded -> (
        match int_of_string_opt encoded with
        | Some value when Protocol_integer.is_safe value -> Ok (`Int value)
        | _ -> Error (path ^ ": integer exceeds the protocol safe range"))
    | `List values ->
        values
        |> List.mapi (fun index value ->
               normalize_json_at (depth + 1)
                 (Printf.sprintf "%s[%d]" path index)
                 value)
        |> List.fold_left
             (fun result value ->
               let* values = result in
               let* value = value in
               Ok (value :: values))
             (Ok [])
        |> Result.map List.rev |> Result.map (fun values -> `List values)
    | `Assoc fields ->
        if List.exists (fun (name, _) -> not (Utf8.is_valid name)) fields then
          Error (path ^ ": object field name must be valid UTF-8")
        else if duplicate_name fields then
          Error (path ^ ": object field names must be unique")
        else
          fields
          |> List.sort (fun (left, _) (right, _) -> String.compare left right)
          |> List.fold_left
               (fun result (name, value) ->
                 let* fields = result in
                 let* value =
                   normalize_json_at (depth + 1) (path ^ "." ^ name) value
                 in
                 Ok ((name, value) :: fields))
               (Ok [])
          |> Result.map List.rev |> Result.map (fun fields -> `Assoc fields)
    | `Float _ -> Error (path ^ ": floating-point values are not supported")
    | `Tuple _ | `Variant _ -> Error (path ^ ": value must be JSON")

let normalize_json path json = normalize_json_at 0 path json

let fields ~path ~required ~optional = function
  | `Assoc fields when duplicate_name fields ->
      Error (path ^ ": object field names must be unique")
  | `Assoc fields ->
      let allowed = required @ optional in
      let names = List.map fst fields in
      (match List.find_opt (fun name -> not (List.mem name allowed)) names with
      | Some name -> Error (path ^ ": unknown field " ^ name)
      | None -> (
          match
            List.find_opt
              (fun name -> not (List.mem_assoc name fields))
              required
          with
          | Some name -> Error (path ^ ": missing field " ^ name)
          | None -> Ok fields))
  | _ -> Error (path ^ " must be an object")

let remaining_seconds deadline = max 0.0 (deadline -. Unix.gettimeofday ())

let rec select_until ~read ~write deadline =
  let remaining = remaining_seconds deadline in
  if remaining <= 0.0 then false
  else
    try
      let readable, writable, _ = Unix.select read write [] remaining in
      readable <> [] || writable <> []
    with Unix.Unix_error (Unix.EINTR, _, _) ->
      select_until ~read ~write deadline

let write_message session deadline message =
  let payload = message ^ "\n" in
  let bytes = Bytes.unsafe_of_string payload in
  let rec loop offset =
    if offset = Bytes.length bytes then Ok ()
    else if not (select_until ~read:[] ~write:[ session.to_extension ] deadline)
    then failure "timeout" "extension request timed out while writing"
    else
      try
        let written =
          Unix.write session.to_extension bytes offset
            (Bytes.length bytes - offset)
        in
        if written = 0 then
          failure "write-failed" "extension stdin accepted no data"
        else loop (offset + written)
      with
      | Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) -> loop offset
      | Unix.Unix_error (Unix.EINTR, _, _) -> loop offset
      | Unix.Unix_error (_, _, _) ->
          failure "write-failed" "could not write extension request"
  in
  loop 0

let line_in_string value =
  match String.index_opt value '\n' with
  | None -> None
  | Some index ->
      let line = String.sub value 0 index in
      let rest_length = String.length value - index - 1 in
      let rest = String.sub value (index + 1) rest_length in
      Some (line, rest)

let read_message session deadline =
  match line_in_string session.unread with
  | Some (line, rest) ->
      session.unread <- rest;
      if String.length line > session.negotiated_max_message_bytes then
        failure "response-too-large" "extension response exceeds the byte limit"
      else Ok line
  | None ->
      let buffer =
        Buffer.create (min 4096 session.negotiated_max_message_bytes)
      in
      Buffer.add_string buffer session.unread;
      session.unread <- "";
      let chunk = Bytes.create 4096 in
      let rec loop () =
        if Buffer.length buffer > session.negotiated_max_message_bytes then
          failure "response-too-large"
            "extension response exceeds the byte limit"
        else if
          not
            (select_until ~read:[ session.from_extension ] ~write:[] deadline)
        then failure "timeout" "extension request timed out while reading"
        else
          try
            let count = Unix.read session.from_extension chunk 0 4096 in
            if count = 0 then
              failure "unexpected-eof"
                "extension stdout ended before a response was complete"
            else
              let rec newline index =
                if index = count then None
                else if Bytes.get chunk index = '\n' then Some index
                else newline (index + 1)
              in
              match newline 0 with
              | None ->
                  Buffer.add_subbytes buffer chunk 0 count;
                  loop ()
              | Some index ->
                  Buffer.add_subbytes buffer chunk 0 index;
                  let rest_length = count - index - 1 in
                  session.unread <-
                    Bytes.sub_string chunk (index + 1) rest_length;
                  if
                    Buffer.length buffer
                    > session.negotiated_max_message_bytes
                  then
                    failure "response-too-large"
                      "extension response exceeds the byte limit"
                  else Ok (Buffer.contents buffer)
          with
          | Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) -> loop ()
          | Unix.Unix_error (Unix.EINTR, _, _) -> loop ()
          | Unix.Unix_error (_, _, _) ->
              failure "read-failed" "could not read extension response"
      in
      loop ()

let parse_json line =
  try
    Yojson.Safe.from_string line |> normalize_json "$response"
    |> Result.map_error (fun message ->
           { code = "invalid-response"; message; data = None })
  with Yojson.Json_error _ | Stack_overflow ->
    failure "invalid-response" "extension response is not valid protocol JSON"

let integer path = function
  | `Int value when Protocol_integer.is_safe value -> Ok value
  | _ -> Error (path ^ " must be a safe integer")

let string path = function
  | `String value when String.length value > 0 && Utf8.is_valid value -> Ok value
  | _ -> Error (path ^ " must be a non-empty UTF-8 string")

let decode_error json =
  match
    fields ~path:"$response.error" ~required:[ "code"; "message" ]
      ~optional:[ "data" ] json
  with
  | Error message -> failure "invalid-response" message
  | Ok fields -> (
      match integer "$response.error.code" (List.assoc "code" fields) with
      | Error message -> failure "invalid-response" message
      | Ok code -> (
          match
            string "$response.error.message" (List.assoc "message" fields)
          with
          | Error message -> failure "invalid-response" message
          | Ok message ->
              let data =
                `Assoc
                  ([ ("jsonRpcCode", `Int code) ]
                  @
                  match List.assoc_opt "data" fields with
                  | None -> []
                  | Some data -> [ ("data", data) ])
              in
              failure ~data "remote-error"
                (Printf.sprintf "extension error %d: %s" code message)))

let decode_response expected_id json =
  match
    fields ~path:"$response" ~required:[ "jsonrpc"; "id" ]
      ~optional:[ "result"; "error" ] json
  with
  | Error message -> failure "invalid-response" message
  | Ok fields -> (
      match List.assoc "jsonrpc" fields with
      | `String "2.0" -> (
          match
            (List.assoc_opt "result" fields, List.assoc_opt "error" fields)
          with
          | Some _, Some _ ->
              failure "invalid-response"
                "extension response contains both result and error"
          | None, None ->
              failure "invalid-response"
                "extension response contains neither result nor error"
          | Some result, None -> (
              match integer "$response.id" (List.assoc "id" fields) with
              | Error message -> failure "invalid-response" message
              | Ok id when id <> expected_id ->
                  failure "invalid-response"
                    "extension response ID does not match"
              | Ok _ -> Ok result)
          | None, Some error -> (
              match List.assoc "id" fields with
              | `Null -> decode_error error
              | id -> (
                  match integer "$response.id" id with
                  | Error message -> failure "invalid-response" message
                  | Ok id when id <> expected_id ->
                      failure "invalid-response"
                        "extension response ID does not match"
                  | Ok _ -> decode_error error)))
      | _ -> failure "invalid-response" "$response.jsonrpc must be \"2.0\"")

let base64_alphabet =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

let base64_encode_substring content offset length =
  let output_length = ((length + 2) / 3) * 4 in
  let output = Bytes.create output_length in
  let byte index = Char.code content.[offset + index] in
  let set index value =
    Bytes.set output index base64_alphabet.[value]
  in
  let rec loop input output_index =
    if input >= length then ()
    else
      let first = byte input in
      let second = if input + 1 < length then byte (input + 1) else 0 in
      let third = if input + 2 < length then byte (input + 2) else 0 in
      set output_index (first lsr 2);
      set (output_index + 1) (((first land 0x03) lsl 4) lor (second lsr 4));
      if input + 1 < length then
        set (output_index + 2)
          (((second land 0x0f) lsl 2) lor (third lsr 6))
      else Bytes.set output (output_index + 2) '=';
      if input + 2 < length then set (output_index + 3) (third land 0x3f)
      else Bytes.set output (output_index + 3) '=';
      loop (input + 3) (output_index + 4)
  in
  loop 0 0;
  Bytes.unsafe_to_string output

let content_descriptor content =
  `Assoc
    [
      ("kind", `String "byteStream");
      ("byteLength", `Int (String.length content));
    ]

let add_content_descriptor params content =
  match params with
  | `Assoc fields when List.mem_assoc "content" fields ->
      Error "$request.params.content is reserved for the host byte stream"
  | `Assoc fields ->
      Ok (`Assoc (("content", content_descriptor content) :: fields))
  | _ -> Error "$request.params must be an object for a content-bearing call"

let notification ~method_name ~params =
  `Assoc
    [
      ("jsonrpc", `String "2.0");
      ("method", `String method_name);
      ("params", params);
    ]
  |> Yojson.Safe.to_string

let chunk_notification ~request_id ~offset ~content ~length =
  notification ~method_name:"monika.contentChunk"
    ~params:
      (`Assoc
        [
          ("requestId", `Int request_id);
          ("offset", `Int offset);
          ("base64", `String (base64_encode_substring content offset length));
        ])

let end_content_notification ~request_id ~byte_length =
  notification ~method_name:"monika.endContent"
    ~params:
      (`Assoc
        [
          ("requestId", `Int request_id);
          ("byteLength", `Int byte_length);
        ])

let maximum_content_chunk_bytes = 48 * 1024

let chunk_length_for session ~request_id ~offset content =
  let remaining = String.length content - offset in
  let rec find length =
    if length <= 0 then
      failure "message-limit-too-small"
        "negotiated extension message limit cannot carry a content chunk"
    else
      let message =
        chunk_notification ~request_id ~offset ~content ~length
      in
      if String.length message <= session.negotiated_max_message_bytes then
        Ok (length, message)
      else find (length / 2)
  in
  find (min maximum_content_chunk_bytes remaining)

let write_content session deadline ~request_id content =
  let rec write_chunks offset =
    if offset = String.length content then Ok ()
    else
      let* length, message =
        chunk_length_for session ~request_id ~offset content
      in
      let* () = write_message session deadline message in
      write_chunks (offset + length)
  in
  let* () = write_chunks 0 in
  let end_message =
    end_content_notification ~request_id ~byte_length:(String.length content)
  in
  if String.length end_message > session.negotiated_max_message_bytes then
    failure "message-limit-too-small"
      "negotiated extension message limit cannot carry the content terminator"
  else write_message session deadline end_message

let valid_method_name value =
  let length = String.length value in
  length > String.length "monika."
  && String.starts_with ~prefix:"monika." value
  && String.for_all
       (function
         | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '.' -> true
         | _ -> false)
       value

let begin_call ?content session ~method_name ~params =
  if not (valid_method_name method_name) then
    failure "invalid-request"
      "extension method must start with monika. and contain only ASCII letters, digits, and dots"
  else if
    match content with
    | Some content ->
        String.length content > session.negotiated_max_content_bytes
    | None -> false
  then
    failure "content-too-large"
      "host-owned Observation content exceeds the negotiated byte limit"
  else
    let params =
      match content with
      | None -> Ok params
      | Some content -> add_content_descriptor params content
    in
    match params with
    | Error message -> failure "invalid-request" message
    | Ok params -> (
    match normalize_json "$request.params" params with
    | Error message -> failure "invalid-request" message
    | Ok _ when not (Protocol_integer.is_safe session.next_id) ->
        failure "request-id-exhausted"
          "extension session exhausted the protocol request ID range"
    | Ok params ->
        let id = session.next_id in
        session.next_id <- session.next_id + 1;
        let request =
          `Assoc
            [
              ("jsonrpc", `String "2.0");
              ("id", `Int id);
              ("method", `String method_name);
              ("params", params);
            ]
          |> Yojson.Safe.to_string
        in
        if String.length request > session.negotiated_max_message_bytes then
          failure "request-too-large" "extension request exceeds the byte limit"
        else
          let deadline =
            Unix.gettimeofday ()
            +. (float_of_int session.limits.request_timeout_ms /. 1000.0)
          in
          let* () = write_message session deadline request in
          let* () =
            match content with
            | None -> Ok ()
            | Some content -> write_content session deadline ~request_id:id content
          in
          Ok (id, deadline))

let raw_call ?content session ~method_name ~params =
  let* id, deadline = begin_call ?content session ~method_name ~params in
  let* response = read_message session deadline in
  let* json = parse_json response in
  decode_response id json

let base64_value = function
  | 'A' .. 'Z' as value -> Char.code value - Char.code 'A'
  | 'a' .. 'z' as value -> Char.code value - Char.code 'a' + 26
  | '0' .. '9' as value -> Char.code value - Char.code '0' + 52
  | '+' -> 62
  | '/' -> 63
  | _ -> -1

let base64_decode encoded =
  if String.length encoded mod 4 <> 0 then Error "invalid base64 length"
  else
    let output = Buffer.create (String.length encoded / 4 * 3) in
    let rec loop offset =
      if offset = String.length encoded then Ok (Buffer.contents output)
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
          || ((third = '=' || fourth = '=')
             && offset + 4 <> String.length encoded)
        then Error "invalid base64 payload"
        else (
          Buffer.add_char output
            (Char.chr ((first lsl 2) lor (second lsr 4)));
          if third <> '=' then
            Buffer.add_char output
              (Char.chr
                 (((second land 0x0f) lsl 4) lor (third_value lsr 2)));
          if fourth <> '=' then
            Buffer.add_char output
              (Char.chr
                 (((third_value land 0x03) lsl 6) lor fourth_value));
          loop (offset + 4))
    in
    loop 0

let output_notification expected_id json =
  let* message_fields =
    fields ~path:"$notification" ~required:[ "jsonrpc"; "method"; "params" ]
      ~optional:[] json
    |> Result.map_error (fun message ->
           { code = "invalid-response"; message; data = None })
  in
  let* () =
    match List.assoc "jsonrpc" message_fields with
    | `String "2.0" -> Ok ()
    | _ -> failure "invalid-response" "$notification.jsonrpc must be \"2.0\""
  in
  let* method_name =
    match List.assoc "method" message_fields with
    | `String value -> Ok value
    | _ -> failure "invalid-response" "$notification.method must be a string"
  in
  let allowed =
    match method_name with
    | "monika.outputContentChunk" -> [ "requestId"; "offset"; "base64" ]
    | "monika.endOutputContent" -> [ "requestId"; "byteLength" ]
    | _ -> []
  in
  if allowed = [] then
    failure "invalid-response" "unexpected Extension notification"
  else
    let* params =
      fields ~path:"$notification.params" ~required:allowed ~optional:[]
        (List.assoc "params" message_fields)
      |> Result.map_error (fun message ->
             { code = "invalid-response"; message; data = None })
    in
    let* request_id =
      integer "$notification.params.requestId" (List.assoc "requestId" params)
      |> Result.map_error (fun message ->
             { code = "invalid-response"; message; data = None })
    in
    if request_id <> expected_id then
      failure "invalid-response"
        "output content notification requestId does not match"
    else Ok (method_name, params)

let raw_call_receiving_content session ~method_name ~params =
  let* id, deadline = begin_call session ~method_name ~params in
  let output = Buffer.create 4096 in
  let rec loop ~started ~ended =
    let* message = read_message session deadline in
    let* json = parse_json message in
    match json with
    | `Assoc fields when List.mem_assoc "id" fields ->
        let* result = decode_response id json in
        if started && not ended then
          failure "invalid-response"
            "Extension response arrived before output content terminator"
        else
          Ok
            ( result,
              if started then Some (Buffer.contents output) else None )
    | _ ->
        if ended then
          failure "invalid-response"
            "Extension sent output content after its terminator"
        else
          let* notification, params = output_notification id json in
          if String.equal notification "monika.outputContentChunk" then
            let* offset =
              integer "$notification.params.offset" (List.assoc "offset" params)
              |> Result.map_error (fun message ->
                     { code = "invalid-response"; message; data = None })
            in
            if offset <> Buffer.length output then
              failure "invalid-response"
                "output content chunks are not contiguous"
            else
              let* encoded =
                match List.assoc "base64" params with
                | `String value -> Ok value
                | _ ->
                    failure "invalid-response"
                      "$notification.params.base64 must be a string"
              in
              let* decoded =
                base64_decode encoded
                |> Result.map_error (fun message ->
                       { code = "invalid-response"; message; data = None })
              in
              if
                String.length decoded
                > session.negotiated_max_content_bytes - Buffer.length output
              then
                failure "content-too-large"
                  "Extension output content exceeds the byte limit"
              else (
                Buffer.add_string output decoded;
                loop ~started:true ~ended:false)
          else
            let* byte_length =
              integer "$notification.params.byteLength"
                (List.assoc "byteLength" params)
              |> Result.map_error (fun message ->
                     { code = "invalid-response"; message; data = None })
            in
            if byte_length <> Buffer.length output then
              failure "invalid-response"
                "output content terminator byteLength does not match"
            else loop ~started:true ~ended:true
  in
  loop ~started:false ~ended:false

let call session ~method_name ~params =
  if not session.initialized then
    failure "session-not-initialized"
      "monika.initializeSession must complete before another extension method"
  else raw_call session ~method_name ~params

let call_with_content session ~method_name ~params ~content =
  if not session.initialized then
    failure "session-not-initialized"
      "monika.initializeSession must complete before another extension method"
  else raw_call ~content session ~method_name ~params

let call_receiving_content session ~method_name ~params =
  if not session.initialized then
    failure "session-not-initialized"
      "monika.initializeSession must complete before another extension method"
  else raw_call_receiving_content session ~method_name ~params

let initialize_session session =
  if session.initialized then
    failure "invalid-request"
      "monika.initializeSession must be called exactly once in a session"
  else
    let params =
      `Assoc
        [
          ("protocolVersions", `List [ `String "1" ]);
          ("maxMessageBytes", `Int session.limits.max_message_bytes);
          ("maxContentBytes", `Int session.limits.max_content_bytes);
        ]
    in
    let* result =
      raw_call session ~method_name:"monika.initializeSession" ~params
    in
    match
      fields ~path:"$response.result"
        ~required:
          [
            "protocolVersion";
            "capability";
            "maxMessageBytes";
            "maxContentBytes";
          ]
        ~optional:[] result
    with
    | Error message -> failure "invalid-response" message
    | Ok result_fields -> (
        match
          integer "$response.result.maxMessageBytes"
            (List.assoc "maxMessageBytes" result_fields)
        with
        | Error message -> failure "invalid-response" message
        | Ok max_message_bytes when max_message_bytes <= 0 ->
            failure "invalid-response"
              "$response.result.maxMessageBytes must be positive"
        | Ok max_message_bytes -> (
            match
              integer "$response.result.maxContentBytes"
                (List.assoc "maxContentBytes" result_fields)
            with
            | Error message -> failure "invalid-response" message
            | Ok max_content_bytes when max_content_bytes <= 0 ->
                failure "invalid-response"
                  "$response.result.maxContentBytes must be positive"
            | Ok max_content_bytes ->
            let manifest_json =
              `Assoc
                [
                  ( "protocolVersion",
                    List.assoc "protocolVersion" result_fields );
                  ("capability", List.assoc "capability" result_fields);
                ]
            in
            (match Extension_manifest.of_yojson manifest_json with
            | Error message ->
                failure "invalid-response"
                  ("invalid manifest returned by monika.initializeSession: "
                 ^ message)
            | Ok manifest ->
                session.negotiated_max_message_bytes <-
                  min session.limits.max_message_bytes max_message_bytes;
                session.negotiated_max_content_bytes <-
                  min session.limits.max_content_bytes max_content_bytes;
                session.initialized <- true;
                Ok manifest)))

let close_noerr descriptor =
  try Unix.close descriptor with Unix.Unix_error _ -> ()

let close_to_extension session =
  if session.to_extension_open then (
    session.to_extension_open <- false;
    close_noerr session.to_extension)

let close_from_extension session =
  if session.from_extension_open then (
    session.from_extension_open <- false;
    close_noerr session.from_extension)

let kill_process_group_noerr pid =
  try Unix.kill (-pid) Sys.sigkill with Unix.Unix_error _ -> ()

let rec reap pid =
  try ignore (Unix.waitpid [] pid) with
  | Unix.Unix_error (Unix.EINTR, _, _) -> reap pid
  | Unix.Unix_error (Unix.ECHILD, _, _) -> ()

let abort session =
  close_to_extension session;
  close_from_extension session;
  kill_process_group_noerr session.pid;
  reap session.pid

let process_status = function
  | Unix.WEXITED 0 -> Ok ()
  | Unix.WEXITED code ->
      failure "process-exit"
        (Printf.sprintf "extension process exited with status %d" code)
  | Unix.WSIGNALED signal ->
      failure "process-exit"
        (Printf.sprintf "extension process was terminated by signal %d" signal)
  | Unix.WSTOPPED signal ->
      failure "process-exit"
        (Printf.sprintf "extension process stopped with signal %d" signal)

let finish session =
  close_to_extension session;
  let deadline =
    Unix.gettimeofday ()
    +. (float_of_int session.limits.shutdown_timeout_ms /. 1000.0)
  in
  let rec wait () =
    try
      match Unix.waitpid [ Unix.WNOHANG ] session.pid with
      | 0, _ ->
          let remaining = remaining_seconds deadline in
          if remaining <= 0.0 then (
            kill_process_group_noerr session.pid;
            reap session.pid;
            failure "shutdown-timeout"
              "extension process did not exit after stdin reached EOF")
          else (
            ignore (Unix.select [] [] [] (min 0.01 remaining));
            wait ())
      | _, status ->
          kill_process_group_noerr session.pid;
          process_status status
    with
    | Unix.Unix_error (Unix.EINTR, _, _) -> wait ()
    | Unix.Unix_error (_, _, _) ->
        kill_process_group_noerr session.pid;
        reap session.pid;
        failure "process-wait-failed" "could not wait for extension process"
  in
  let result = wait () in
  close_from_extension session;
  result

let validate_command executable arguments =
  let rec arguments_exceed_byte_limit remaining = function
    | [] -> false
    | argument :: rest ->
        let length = String.length argument in
        length > remaining
        || arguments_exceed_byte_limit (remaining - length) rest
  in
  if String.length executable = 0 then Error "executable must not be empty"
  else if not (Utf8.is_valid executable) || contains_nul executable then
    Error "executable must be UTF-8 and contain no NUL"
  else if
    List.exists
      (fun argument -> not (Utf8.is_valid argument) || contains_nul argument)
      arguments
  then Error "extension arguments must be UTF-8 and contain no NUL"
  else if List.length arguments > 128 then
    Error "extension arguments exceed the 128-argument limit"
  else if arguments_exceed_byte_limit (64 * 1024) arguments then
    Error "extension arguments exceed the 64 KiB byte limit"
  else Ok ()

let create_pipes () =
  try
    let child_stdin, parent_write = Unix.pipe ~cloexec:true () in
    try
      let parent_read, child_stdout = Unix.pipe ~cloexec:true () in
      Ok (child_stdin, parent_write, parent_read, child_stdout)
    with Unix.Unix_error _ | Sys_error _ ->
      close_noerr child_stdin;
      close_noerr parent_write;
      Error "could not create extension process pipes"
  with Unix.Unix_error _ | Sys_error _ ->
    Error "could not create extension process pipes"

let child_setup_message = function
  | 1 -> "could not create an isolated extension process group"
  | 2 -> "could not enter the bounded extension scratch directory"
  | 3 -> "could not apply extension process resource limits"
  | _ -> "could not prepare the extension sandbox process"

let write_setup_failure descriptor code =
  let payload = Bytes.make 1 (Char.chr code) in
  let rec write () =
    try ignore (Unix.write descriptor payload 0 1) with
    | Unix.Unix_error (Unix.EINTR, _, _) -> write ()
    | Unix.Unix_error _ -> ()
  in
  write ()

let child_exec prepared ~child_stdin ~parent_write ~parent_read ~child_stdout
    ~setup_read ~setup_write =
  close_noerr setup_read;
  close_noerr parent_write;
  close_noerr parent_read;
  (try
     Unix.dup2 ~cloexec:false child_stdin Unix.stdin;
     Unix.dup2 ~cloexec:false child_stdout Unix.stdout;
     let setup_code =
       extension_child_setup (Extension_sandbox.scratch prepared)
         Extension_sandbox.scratch_limit_bytes setup_write
     in
     if setup_code <> 0 then (
       write_setup_failure setup_write setup_code;
       Unix._exit 125)
     else
       Unix.execve (Extension_sandbox.executable prepared)
         (Extension_sandbox.arguments prepared)
         (Extension_sandbox.environment prepared)
   with Unix.Unix_error _ | Sys_error _ ->
     write_setup_failure setup_write 4;
     Unix._exit 125)

let read_setup_status descriptor =
  let payload = Bytes.create 1 in
  let rec read () =
    try
      match Unix.read descriptor payload 0 1 with
      | 0 -> Ok ()
      | _ -> Error (Char.code (Bytes.get payload 0))
    with
    | Unix.Unix_error (Unix.EINTR, _, _) -> read ()
    | Unix.Unix_error _ -> Error 4
  in
  read ()

let spawn_prepared prepared child_stdin parent_write parent_read child_stdout =
  match Unix.pipe ~cloexec:true () with
  | exception Unix.Unix_error _ | exception Sys_error _ ->
      Error "could not start sandboxed extension process"
  | setup_read, setup_write -> (
      try
        match Unix.fork () with
        | 0 ->
            child_exec prepared ~child_stdin ~parent_write ~parent_read
              ~child_stdout ~setup_read ~setup_write
        | pid ->
            close_noerr setup_write;
            let status = read_setup_status setup_read in
            close_noerr setup_read;
            (match status with
            | Ok () -> Ok pid
            | Error code ->
                kill_process_group_noerr pid;
                reap pid;
                Error (child_setup_message code))
      with Unix.Unix_error _ | Sys_error _ ->
        close_noerr setup_read;
        close_noerr setup_write;
        Error "could not start sandboxed extension process")

let with_session ~executable ~arguments ~authority ~limits operation =
  match validate_command executable arguments with
  | Error message -> failure "invalid-command" message
  | Ok () -> (
      match Extension_sandbox.prepare ~executable ~arguments ~authority with
      | Error message -> failure "sandbox-setup-failed" message
      | Ok prepared ->
      Fun.protect ~finally:(fun () -> Extension_sandbox.cleanup prepared) (fun () ->
      match create_pipes () with
      | Error message -> failure "pipe-failed" message
      | Ok (child_stdin, parent_write, parent_read, child_stdout) ->
          let pid_result =
            spawn_prepared prepared child_stdin parent_write parent_read
              child_stdout
          in
          close_noerr child_stdin;
          close_noerr child_stdout;
          (match pid_result with
          | Error message ->
              close_noerr parent_write;
              close_noerr parent_read;
              failure "spawn-failed" message
          | Ok pid ->
              let session =
                {
                  pid;
                  from_extension = parent_read;
                  to_extension = parent_write;
                  limits;
                  to_extension_open = true;
                  from_extension_open = true;
                  unread = "";
                  next_id = 1;
                  negotiated_max_message_bytes = limits.max_message_bytes;
                  negotiated_max_content_bytes = limits.max_content_bytes;
                  initialized = false;
                }
              in
              (try
                 let setup =
                   try
                     Unix.set_nonblock parent_write;
                     Unix.set_nonblock parent_read;
                     Ok ()
                   with Unix.Unix_error _ | Sys_error _ ->
                     Error "could not configure extension process pipes"
                 in
                 match setup with
                 | Error message ->
                     abort session;
                     failure "pipe-failed" message
                 | Ok () -> (
                     match operation session with
                     | Error _ as error ->
                         abort session;
                         error
                     | Ok value -> (
                         match finish session with
                         | Ok () -> Ok value
                         | Error _ as error -> error))
               with exception_raised ->
                 abort session;
                 let _ = exception_raised in
                 failure "host-operation-exception"
                   "extension host operation raised unexpectedly"))))

let with_checked_session ~executable ~arguments ~authority ~limits ~manifest operation =
  match
    Extension_authority.validate_for_capability
      (Extension_manifest.capability manifest) authority
  with
  | Error message -> failure "invalid-authority" message
  | Ok () ->
      with_session ~executable ~arguments ~authority ~limits (fun session ->
          let* runtime_manifest = initialize_session session in
          if Extension_manifest.equal manifest runtime_manifest then
            operation session
          else
            failure "manifest-mismatch"
              "extension runtime manifest does not match the static manifest")
