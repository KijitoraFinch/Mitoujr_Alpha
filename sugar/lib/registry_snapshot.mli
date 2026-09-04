(** An immutable snapshot of extension installation state. Capability
    identities are unique within a snapshot. *)
type t

val empty : t
val make : Installed_extension.t list -> (t, string) result
val extensions : t -> Installed_extension.t list

val find_interpreter :
  t -> Interpreter.t -> Installed_extension.t option

(** All installed capabilities of [kind] whose declarative applicability
    accepts the already fixed Observation. The order is canonical. *)
val applicable :
  t ->
  kind:Capability.kind ->
  observation:Observation.t ->
  (Installed_extension.t list, string) result

val of_yojson : Yojson.Safe.t -> (t, string) result
val load : string -> (t, string) result
