type prepared

val prepare :
  executable:string ->
  arguments:string list ->
  authority:Extension_authority.t ->
  (prepared, string) result

val resolve_executable : string -> (string, string) result
val executable : prepared -> string
val arguments : prepared -> string array
val environment : prepared -> string array
val scratch : prepared -> string
val scratch_limit_bytes : int
val cleanup : prepared -> unit
val platform : unit -> string
