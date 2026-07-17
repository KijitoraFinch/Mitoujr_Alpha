type t = private {
  artifact : Artifact.origin;
  selector : Selector.t;
  interpreter : string option;
}

val make :
  artifact:Artifact.origin ->
  selector:Selector.t ->
  ?interpreter:string ->
  unit ->
  (t, string) result

val artifact : t -> Artifact.origin
val selector : t -> Selector.t
val interpreter : t -> string option
val compare : t -> t -> int
