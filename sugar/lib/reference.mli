type binding = Pinned | Tracking | Floating

type target = Region_address.t

type t

val make_target :
  origin:Observation.origin ->
  selector:Selector.t ->
  ?interpreter:string ->
  ?interpreter_version:string ->
  unit ->
  (target, string) result

val make :
  id:Reference_id.t ->
  target:target ->
  binding:binding ->
  ?expectations:Expectation.t list ->
  unit ->
  t

val id : t -> Reference_id.t
val target : t -> target
val binding : t -> binding
val expectations : t -> Expectation.t list
val target_origin : target -> Observation.origin
val target_selector : target -> Selector.t
val target_interpreter : target -> string option
val target_interpreter_version : target -> string option
val compare_target : target -> target -> int
val compare : t -> t -> int
val equal : t -> t -> bool
