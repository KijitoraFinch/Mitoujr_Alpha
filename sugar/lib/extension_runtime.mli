type limits
type failure
type session

val default_limits : limits

val make_limits :
  max_message_bytes:int ->
  request_timeout_ms:int ->
  shutdown_timeout_ms:int ->
  unit ->
  (limits, string) result

val max_message_bytes : limits -> int
val request_timeout_ms : limits -> int
val shutdown_timeout_ms : limits -> int

val failure_code : failure -> string
val failure_message : failure -> string

val with_session :
  executable:string ->
  arguments:string list ->
  limits:limits ->
  (session -> ('a, failure) result) ->
  ('a, failure) result

val with_checked_session :
  executable:string ->
  arguments:string list ->
  limits:limits ->
  manifest:Extension_manifest.t ->
  (session -> ('a, failure) result) ->
  ('a, failure) result

val call :
  session ->
  method_name:string ->
  params:Yojson.Safe.t ->
  (Yojson.Safe.t, failure) result

val initialize_session : session -> (Extension_manifest.t, failure) result
