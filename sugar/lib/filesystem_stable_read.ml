type 'value observation = Stable of 'value | Changed
type attempts = int

let make_attempts value =
  if value <= 0 then Error "stable read attempts must be positive" else Ok value

let twice = 2

let retry ~attempts ~on_unstable attempt =
  let rec loop remaining =
    match attempt () with
    | Error _ as error -> error
    | Ok (Stable value) -> Ok value
    | Ok Changed ->
        if remaining = 1 then Error on_unstable else loop (remaining - 1)
  in
  loop attempts
