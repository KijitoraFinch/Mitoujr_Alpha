# Linking Fixture

<!-- monika:region id=claim-sidecar-friction -->

The latency claim uses [run A](../runs/metrics.jsonl#latency-run-a) and is supported by the named reference.

<!-- monika:annotation id=inline-only predicate=supported-by ref=latency-run-a -->

<!-- monika:annotation id=divergent predicate=supported-by ref=latency-run-a -->

The throughput claim intentionally has a different sidecar representation for
the divergent diagnostic case.

<!-- monika:region id=stale-claim-old -->

This region is current while the sidecar targets a removed ID, so executable stale-selector auditing detects it.
