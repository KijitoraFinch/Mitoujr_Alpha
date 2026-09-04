(** Converts an unexpected OCaml exception into an explicit internal-error
    command result. The exception text is deliberately not exposed as protocol
    data because it is neither stable nor guaranteed to be free of input data. *)
val protect : (unit -> 'a) -> ('a, Command_result.t) result
