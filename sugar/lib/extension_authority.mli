type origin_class = Extension

type t

val default_sandboxed : t
val sandboxed : launch_paths:string list -> (t, string) result

val resource_observer :
  launch_paths:string list ->
  resource_read_paths:string list ->
  network:bool ->
  (t, string) result

val launch_paths : t -> string list
val resource_read_paths : t -> string list
val network : t -> bool
val origin_class : t -> origin_class option
val is_absolute_path : string -> bool
val validate_for_capability : Capability.t -> t -> (unit, string) result
val of_yojson : Yojson.Safe.t -> (t, string) result
val to_yojson : t -> Yojson.Safe.t
val compare : t -> t -> int
