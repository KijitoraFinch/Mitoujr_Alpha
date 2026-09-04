type t

val make :
  interpreter:Interpreter.t ->
  observation_identity:Observation_identity.t ->
  selector:Selector.t ->
  t

val interpreter : t -> Interpreter.t
val observation_identity : t -> Observation_identity.t
val selector : t -> Selector.t
val compare : t -> t -> int
val equal : t -> t -> bool
