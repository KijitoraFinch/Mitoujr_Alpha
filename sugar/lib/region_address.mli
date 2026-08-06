type t = private {
  artifact : Artifact.origin;
  selector : Selector.t;
  interpreter : string option;
  interpreter_version : string option;
}

val make :
  artifact:Artifact.origin ->
  selector:Selector.t ->
  ?interpreter:string ->
  ?interpreter_version:string ->
  unit ->
  (t, string) result

val artifact : t -> Artifact.origin
val selector : t -> Selector.t
val interpreter : t -> string option
val interpreter_version : t -> string option
val interpreter_identity : t -> Interpreter.t option
val compare : t -> t -> int
