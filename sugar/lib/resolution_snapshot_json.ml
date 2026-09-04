let maximum_snapshot_bytes = 1024 * 1024

let load path =
  try
    let input = open_in_bin path in
    Fun.protect ~finally:(fun () -> close_in_noerr input) (fun () ->
        let length = in_channel_length input in
        if length > maximum_snapshot_bytes then
          Error "resolution snapshot exceeds the 1 MiB size limit"
        else
          let content = really_input_string input length in
          if not (Utf8.is_valid content) then
            Error "resolution snapshot must be UTF-8 JSON"
          else
            try Yojson.Safe.from_string content |> Normal_decode.resolution_snapshot
            with Yojson.Json_error message ->
              Error ("resolution snapshot is not valid JSON: " ^ message))
  with Sys_error message -> Error message
