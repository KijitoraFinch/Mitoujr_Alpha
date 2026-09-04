let protect operation =
  try Ok (operation ()) with
  | _ ->
      Error
        (Command_result.internal_error ~command:"monika"
           ~error_code:"unhandled-exception" ~operation:"command-dispatch")
