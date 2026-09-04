let select_all registry observation =
  Registry_snapshot.applicable registry
    ~kind:Capability.Reference_extractor ~observation
