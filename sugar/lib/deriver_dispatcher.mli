type selected = Built_in_inline_to_sidecar | Installed of Installed_extension.t

(** Exact identity selection for a DeriveRequest. *)
val find_exact :
  Registry_snapshot.t ->
  name:string ->
  version:string ->
  (selected option, string) result
