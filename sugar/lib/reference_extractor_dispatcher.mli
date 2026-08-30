(** Selects every installed Reference Extractor applicable to a fixed
    Observation. Definition and use results are additive. *)
val select_all :
  Registry_snapshot.t ->
  Observation.t ->
  (Installed_extension.t list, string) result
