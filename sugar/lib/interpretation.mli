type t

val make :
  interpreter:Interpreter.t ->
  observation:Observation.t ->
  regions:Region.t list ->
  (t, string) result

val interpreter : t -> Interpreter.t
val observation : t -> Observation_id.t
val regions : t -> Region.t list
