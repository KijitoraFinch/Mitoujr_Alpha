type limits = {
  max_message_bytes : int;
  request_timeout_ms : int;
  shutdown_timeout_ms : int;
}

type failure = {
  code : string;
  message : string;
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
  mutable initialized : bool;
}

let ( let* ) = Result.bind

let default_limits =
  {
    max_message_bytes = 16 * 1024 * 1024;
    request_timeout_ms = 30_000;
    shutdown_timeout_ms = 1_000;
  }

let make_limits ~max_message_bytes ~request_timeout_ms ~shutdown_timeout_ms () =
  if max_message_bytes <= 0 then Error "max_message_bytes must be positive"
  else if not (Protocol_integer.is_safe max_message_bytes) then
    Error "max_message_bytes exceeds the protocol safe-integer range"
  else if request_timeout_ms <= 0 then
    Error "request_timeout_ms must be positive"
  else if not (Protocol_integer.is_safe request_timeout_ms) then
    Error "request_timeout_ms exceeds the protocol safe-integer range"
  else if shutdown_timeout_ms <= 0 then
    Error "shutdown_timeout_ms must be positive"
  else if not (Protocol_integer.is_safe shutdown_timeout_ms) then
    Error "shutdown_timeout_ms exceeds the protocol safe-integer range"
  else Ok { max_message_bytes; request_timeout_ms; shutdown_timeout_ms }

let max_message_bytes value = value.max_message_bytes
let request_timeout_ms value = value.request_timeout_ms
let shutdown_timeout_ms value = value.shutdown_timeout_ms
let failure code message = Error { code; message }
let failure_code value = value.code
let failure_message value = value.message

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
           { code = "invalid-response"; message })
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
              failure "remote-error"
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

let valid_method_name value =
  let length = String.length value in
  length > String.length "monika."
  && String.starts_with ~prefix:"monika." value
  && String.for_all
       (function
         | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '.' -> true
         | _ -> false)
       value

let raw_call session ~method_name ~params =
  if not (valid_method_name method_name) then
    failure "invalid-request"
      "extension method must start with monika. and contain only ASCII letters, digits, and dots"
  else
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
          let* response = read_message session deadline in
          let* json = parse_json response in
          decode_response id json

let call session ~method_name ~params =
  if not session.initialized then
    failure "session-not-initialized"
      "monika.initializeSession must complete before another extension method"
  else raw_call session ~method_name ~params

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
        ]
    in
    let* result =
      raw_call session ~method_name:"monika.initializeSession" ~params
    in
    match
      fields ~path:"$response.result"
        ~required:[ "protocolVersion"; "capability"; "maxMessageBytes" ]
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
        | Ok max_message_bytes ->
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
                session.initialized <- true;
                Ok manifest))

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

let kill_noerr pid =
  try Unix.kill pid Sys.sigkill with Unix.Unix_error _ -> ()

let rec reap pid =
  try ignore (Unix.waitpid [] pid) with
  | Unix.Unix_error (Unix.EINTR, _, _) -> reap pid
  | Unix.Unix_error (Unix.ECHILD, _, _) -> ()

let abort session =
  close_to_extension session;
  close_from_extension session;
  kill_noerr session.pid;
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
            kill_noerr session.pid;
            reap session.pid;
            failure "shutdown-timeout"
              "extension process did not exit after stdin reached EOF")
          else (
            ignore (Unix.select [] [] [] (min 0.01 remaining));
            wait ())
      | _, status -> process_status status
    with
    | Unix.Unix_error (Unix.EINTR, _, _) -> wait ()
    | Unix.Unix_error (_, _, _) ->
        failure "process-wait-failed" "could not wait for extension process"
  in
  let result = wait () in
  close_from_extension session;
  result

let validate_command executable arguments =
  if String.length executable = 0 then Error "executable must not be empty"
  else if contains_nul executable then Error "executable must not contain NUL"
  else if List.exists contains_nul arguments then
    Error "extension arguments must not contain NUL"
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

let with_session ~executable ~arguments ~limits operation =
  match validate_command executable arguments with
  | Error message -> failure "invalid-command" message
  | Ok () -> (
      match create_pipes () with
      | Error message -> failure "pipe-failed" message
      | Ok (child_stdin, parent_write, parent_read, child_stdout) ->
          let pid_result =
            try
              let arguments = Array.of_list (executable :: arguments) in
              Ok
                (Unix.create_process executable arguments child_stdin
                   child_stdout Unix.stderr)
            with
            | Unix.Unix_error _ | Sys_error _ ->
                Error "could not start extension executable"
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
                   "extension host operation raised unexpectedly")))

let with_checked_session ~executable ~arguments ~limits ~manifest operation =
  with_session ~executable ~arguments ~limits (fun session ->
      let* runtime_manifest = initialize_session session in
      if Extension_manifest.equal manifest runtime_manifest then
        operation session
      else
        failure "manifest-mismatch"
          "extension runtime manifest does not match the static manifest")
