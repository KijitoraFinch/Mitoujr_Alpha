type selected = Built_in_workspace_file | Installed of Installed_extension.t

(** Origin-directed Resource Observer selection. Extension origins require an
    exact observer identity; workspace paths always use the built-in observer. *)
val select :
  Registry_snapshot.t -> Origin.t -> (selected option, string) result
