/**
 * @monika annotation id=source-comment-annotation predicate=implements object=ref:latency-run-a
 */
export function resolveLatency(sample: { metric: string; value: number }): number | null {
  if (sample.metric !== "latency") {
    return null;
  }

  return sample.value;
}
