type result =
  | Unsupported
  | Failure of {
      capability : Capability.t option;
      failure : Extension_failure.t;
    }
  | Observed of {
      capability : Capability.t;
      observation : Observation.t;
    }

val observe : Registry_snapshot.t -> Origin.t -> (result, string) Stdlib.result
