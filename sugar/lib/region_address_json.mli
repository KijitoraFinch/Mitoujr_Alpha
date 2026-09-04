(** Load one standalone normalized RegionAddress from a bounded UTF-8 JSON
    file. *)
val load : string -> (Region_address.t, string) result
