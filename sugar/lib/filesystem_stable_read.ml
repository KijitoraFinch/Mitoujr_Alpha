type 'value observation = Stable of 'value | Changed

let retry ~attempts ~on_unstable attempt =
  if attempts <= 0 then invalid_arg "stable read attempts must be positive";
  let rec loop remaining =
    match attempt () with
    | Error _ as error -> error
    | Ok (Stable value) -> Ok value
    | Ok Changed ->
        if remaining = 1 then Error on_unstable else loop (remaining - 1)
  in
  loop attempts
