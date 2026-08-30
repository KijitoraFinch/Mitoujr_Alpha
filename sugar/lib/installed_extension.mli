(** A manifest paired with the command authorized by installation state. This
    value is not part of a workspace and is never inferred from workspace
    configuration. *)
type t

val make :
  manifest:Extension_manifest.t ->
  executable:string ->
  arguments:string list ->
  (t, string) result

val manifest : t -> Extension_manifest.t
val capability : t -> Capability.t
val executable : t -> string
val arguments : t -> string list
val compare : t -> t -> int
