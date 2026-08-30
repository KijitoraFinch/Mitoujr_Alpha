(** Load one standalone normalized ResolutionSnapshot from a bounded UTF-8 JSON
    file. *)
val load : string -> (Resolution_snapshot.t, string) result
