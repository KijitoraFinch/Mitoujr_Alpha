type binding = Pinned | Tracking | Floating

type target = {
  artifact : Artifact.origin;
  selector : Selector.t option;
  interpreter : string option;
}

type t

val make :
  id:Identifier.t ->
  target:target ->
  binding:binding ->
  ?expectations:Expectation.t list ->
  ?provenance:Provenance.t list ->
  unit ->
  t

val id : t -> Identifier.t
val target : t -> target
val binding : t -> binding
val expectations : t -> Expectation.t list
val provenance : t -> Provenance.t list
val compare_target : target -> target -> int
