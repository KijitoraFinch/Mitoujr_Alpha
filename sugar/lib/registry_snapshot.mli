(** An immutable snapshot of extension installation state. Capability
    identities are unique within a snapshot. *)
type t

val empty : t
val make : Installed_extension.t list -> (t, string) result
val extensions : t -> Installed_extension.t list

val find_interpreter :
  t -> Interpreter.t -> Installed_extension.t option

val of_yojson : Yojson.Safe.t -> (t, string) result
val load : string -> (t, string) result
