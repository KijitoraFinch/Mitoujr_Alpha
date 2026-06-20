type t

val make :
  id:Identifier.t ->
  artifact:Identifier.t ->
  selector:Selector.t ->
  interpreter:string ->
  ?summary:string ->
  ?range:Text_range.t ->
  ?fingerprint:string ->
  unit ->
  (t, string) result

val id : t -> Identifier.t
val artifact : t -> Identifier.t
val selector : t -> Selector.t
val interpreter : t -> string
val summary : t -> string option
val range : t -> Text_range.t option
val fingerprint : t -> string option
