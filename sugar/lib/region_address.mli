type t

val make :
  origin:Observation.origin ->
  selector:Selector.t ->
  ?interpreter:string ->
  ?interpreter_version:string ->
  unit ->
  (t, string) result

val origin : t -> Observation.origin
val selector : t -> Selector.t
val interpreter : t -> string option
val interpreter_version : t -> string option
val interpreter_identity : t -> Interpreter.t option
val compare : t -> t -> int
