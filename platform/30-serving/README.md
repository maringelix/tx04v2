# platform/30-serving — model serving + autoscaling

> **Docker-only:** use `.\lab.ps1 serving` and `.\lab.ps1 kubectl ...` (or
> `./lab.sh`). Helm and kubectl live in the toolbox image, not on the host.

Deploys a runnable **mock inference server** and autoscales it on **concurrency
(in-flight requests)** — the pattern you'd use for real LLM serving, minus the
GPU cost.

## Run the autoscaling demo

```bash
kubectl apply -f platform/30-serving/mock-llm.yaml
kubectl apply -f platform/30-serving/servicemonitor.yaml      # needs observability module

# custom-metric HPA (needs prometheus-adapter):
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install prom-adapter prometheus-community/prometheus-adapter \
  -n monitoring -f platform/30-serving/prometheus-adapter-values.yaml
kubectl apply -f platform/30-serving/hpa.yaml

# ...or the zero-dependency CPU fallback:
kubectl -n serving autoscale deploy/mock-llm --cpu-percent=50 --min=1 --max=8

# drive load and watch it scale
kubectl apply -f platform/30-serving/loadgen.yaml
kubectl -n serving get hpa mock-llm -w
```

## How the HPA loop actually works (under the hood)

1. Every 15s the HPA controller reads the metric for the target's pods from one
   of three APIs:
   - `metrics.k8s.io` (metrics-server) — CPU/memory only.
   - `custom.metrics.k8s.io` (prometheus-adapter) — our `llm_requests_inflight`.
   - `external.metrics.k8s.io` (KEDA) — queue length, cloud metrics, etc.
2. It computes `desiredReplicas = ceil(currentReplicas * currentMetric / target)`.
3. `behavior` policies + stabilization windows damp the change (fast up, slow
   down here) to avoid thrashing.

So the metrics **pipeline** matters as much as the HPA: Service → ServiceMonitor
→ Prometheus → prometheus-adapter → custom.metrics API → HPA. Break any link and
the HPA silently falls back to "can't read metric / no scale."

## Why concurrency, not CPU, for inference (talking points)

- For a **GPU** server, CPU is nearly idle while the GPU is saturated — CPU% is a
  useless scale signal. **Queue depth / in-flight requests** tracks real load.
- **Cold start dominates GPU autoscaling.** Adding a replica means: schedule onto
  a (maybe not-yet-existent) GPU node → pull a multi-GB image → load model weights
  into VRAM. That's minutes, not seconds. Mitigations: warm pools, node
  over-provisioning (pause pods), image pre-pull, model caching on a PVC, and
  **scale-to-zero with KEDA** for spiky traffic to claw back cost.
- **HPA vs VPA vs Cluster Autoscaler vs Karpenter:** HPA changes *replica count*,
  VPA changes *pod requests*, Cluster Autoscaler/Karpenter change *node count*.
  For GPUs they compose: HPA wants more pods → pods go Pending (Insufficient
  nvidia.com/gpu) → CA/Karpenter provisions GPU nodes.
- **Continuous batching + KV-cache** (real vLLM, see `real-vllm/`) are why one GPU
  can serve many concurrent requests; throughput and VRAM both scale with batch.

## Files

| File | Purpose |
|------|---------|
| `mock-llm.yaml` | stdlib-Python inference stub: `/generate`, `/metrics` (in-flight gauge), `/healthz` |
| `hpa.yaml` | autoscaling/v2 HPA on `llm_requests_inflight` (+ CPU fallback in comments) |
| `prometheus-adapter-values.yaml` | publishes the custom metric to `custom.metrics.k8s.io` |
| `servicemonitor.yaml` | Prometheus scrape config (label `release: kube-prom`) |
| `loadgen.yaml` | concurrent load generator |
| `real-vllm/` | optional real vLLM reference |

## JD coverage
Autoscaling, developer experience, cost efficiency; LLM fundamentals (batching,
KV-cache); observability-driven scaling; explaining the metrics pipeline end-to-end.
