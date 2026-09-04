(** Selects every installed Annotation Extractor applicable to a fixed
    Observation. Results are additive and remain in registry order. *)
val select_all :
  Registry_snapshot.t ->
  Observation.t ->
  (Installed_extension.t list, string) result
