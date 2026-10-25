# Real vLLM (optional, heavy)

`vllm-cpu.yaml` runs an actual [vLLM](https://docs.vllm.ai) OpenAI-compatible
server with a tiny model. It's a reference — the lab's default path uses the
lightweight `mock-llm` so the autoscaling lesson runs on 8 GB.

```bash
kubectl apply -f platform/30-serving/real-vllm/vllm-cpu.yaml
kubectl -n serving port-forward svc/vllm 8000:80
curl http://localhost:8000/v1/completions \
  -H 'content-type: application/json' \
  -d '{"model":"facebook/opt-125m","prompt":"Kubernetes is","max_tokens":16}'
```

## What vLLM does that a naive server doesn't

- **Continuous (in-flight) batching** — instead of waiting to assemble a fixed
  batch, vLLM adds/removes sequences from the running batch every decode step, so
  the GPU stays busy and latency stays low under mixed load.
- **PagedAttention / KV-cache** — attention keys/values are stored in fixed-size
  "pages" so memory isn't fragmented and long contexts don't waste VRAM. The
  KV-cache is usually what actually fills VRAM (see `scenarios/b-vram-oom`).
- **Prometheus metrics** — `vllm:num_requests_running` and
  `vllm:num_requests_waiting` are the production autoscale signals; point a
  ServiceMonitor + prometheus-adapter/KEDA at them exactly like the mock.

## Production serving patterns

| Pattern | When |
|---------|------|
| Raw `Deployment` + Service | simplest; you own autoscaling/routing |
| **KServe `InferenceService`** | standardized CRD: canary, scale-to-zero, transformers, autoscaling |
| **vLLM** (in either) | the actual high-throughput LLM engine |
| **KEDA** | event/queue-driven autoscaling incl. **scale-to-zero** (huge cost win for spiky GPU inference) |
