type binding = Pinned | Tracking | Floating

type target = Region_address.t

type t

val make_target :
  artifact:Artifact.origin ->
  selector:Selector.t ->
  ?interpreter:string ->
  unit ->
  (target, string) result

val make :
  id:Reference_id.t ->
  target:target ->
  binding:binding ->
  ?expectations:Expectation.t list ->
  ?provenance:Provenance.t list ->
  unit ->
  t

val id : t -> Reference_id.t
val target : t -> target
val binding : t -> binding
val expectations : t -> Expectation.t list
val provenance : t -> Provenance.t list
val target_artifact : target -> Artifact.origin
val target_selector : target -> Selector.t
val target_interpreter : target -> string option
val compare_target : target -> target -> int
