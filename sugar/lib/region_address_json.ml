let maximum_address_bytes = 1024 * 1024

let load path =
  try
    let input = open_in_bin path in
    Fun.protect ~finally:(fun () -> close_in_noerr input) (fun () ->
        let length = in_channel_length input in
        if length > maximum_address_bytes then
          Error "RegionAddress exceeds the 1 MiB size limit"
        else
          let content = really_input_string input length in
          if not (Utf8.is_valid content) then
            Error "RegionAddress must be UTF-8 JSON"
          else
            try Yojson.Safe.from_string content |> Normal_decode.region_address
            with Yojson.Json_error message ->
              Error ("RegionAddress is not valid JSON: " ^ message))
  with Sys_error message -> Error message
