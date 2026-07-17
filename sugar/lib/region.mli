type t

val make :
  id:Region_id.t ->
  selector:Selector.t ->
  interpreter:string ->
  ?summary:string ->
  ?range:Text_range.t ->
  ?fingerprint:string ->
  unit ->
  (t, string) result

val id : t -> Region_id.t
val artifact : t -> Artifact_id.t
val selector : t -> Selector.t
val interpreter : t -> string
val summary : t -> string option
val range : t -> Text_range.t option
val fingerprint : t -> string option
