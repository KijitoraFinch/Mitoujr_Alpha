type limits
type failure
type session

val default_limits : limits

val make_limits :
  max_message_bytes:int ->
  ?max_content_bytes:int ->
  request_timeout_ms:int ->
  shutdown_timeout_ms:int ->
  unit ->
  (limits, string) result

val max_message_bytes : limits -> int
val max_content_bytes : limits -> int
val request_timeout_ms : limits -> int
val shutdown_timeout_ms : limits -> int

val failure_code : failure -> string
val failure_message : failure -> string
val failure_data : failure -> Yojson.Safe.t option

val with_session :
  executable:string ->
  arguments:string list ->
  authority:Extension_authority.t ->
  limits:limits ->
  (session -> ('a, failure) result) ->
  ('a, failure) result

val with_checked_session :
  executable:string ->
  arguments:string list ->
  authority:Extension_authority.t ->
  limits:limits ->
  manifest:Extension_manifest.t ->
  (session -> ('a, failure) result) ->
  ('a, failure) result

val call :
  session ->
  method_name:string ->
  params:Yojson.Safe.t ->
  (Yojson.Safe.t, failure) result

val call_with_content :
  session ->
  method_name:string ->
  params:Yojson.Safe.t ->
  content:string ->
  (Yojson.Safe.t, failure) result

(** Calls a method that may stream one finite byte value from the Extension to
    the host before returning its JSON-RPC response. *)
val call_receiving_content :
  session ->
  method_name:string ->
  params:Yojson.Safe.t ->
  (Yojson.Safe.t * string option, failure) result

val initialize_session : session -> (Extension_manifest.t, failure) result
