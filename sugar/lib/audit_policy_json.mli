val encode : Audit_policy.t -> Yojson.Safe.t
val of_yojson : Yojson.Safe.t -> (Audit_policy.t, string) result
val load : string -> (Audit_policy.t, string) result
