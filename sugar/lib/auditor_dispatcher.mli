type selected = Built_in_workspace_check | Installed of Installed_extension.t

(** All Auditors enabled by the current built-in policy. Auditor diagnostics
    are additive. *)
val select_all : Registry_snapshot.t -> selected list
