type t

val make :
  id:Region_id.t ->
  observation_identity:Observation_identity.t ->
  selector:Selector.t ->
  interpreter:Interpreter.t ->
  ?summary:string ->
  ?range:Text_range.t ->
  ?fingerprint:string ->
  unit ->
  (t, string) result

val whole :
  id:Region_id.t -> observation_identity:Observation_identity.t -> t

val id : t -> Region_id.t
val artifact : t -> Artifact_id.t
val observation_identity : t -> Observation_identity.t
val selector : t -> Selector.t
val interpreter : t -> string option
val interpreter_identity : t -> Interpreter.t option
val summary : t -> string option
val range : t -> Text_range.t option
val fingerprint : t -> string option
