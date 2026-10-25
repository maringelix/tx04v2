# platform/50-observability — Prometheus + Grafana + DCGM

> **Docker-only:** install with `.\lab.ps1 observability` or
> `./lab.sh observability`. Run kubectl/Helm through the launcher.

GPU observability is where a platform engineer earns their keep: the device
plugin only tells you *how many* GPUs exist; **DCGM** tells you what they're
*doing*. This module installs the Prometheus/Grafana stack and wires in the GPU
telemetry, dashboards, and alerts.

## Install

```bash
bash platform/50-observability/install.sh
./lab.sh grafana                                                          # -> http://localhost:3001 (admin/admin)
./lab.sh prometheus                                                       # -> http://localhost:9090
# raw equivalents (bind only inside the toolbox; prefer the launcher verbs above):
kubectl -n monitoring port-forward svc/kube-prom-grafana 3001:80          # admin/admin (3001, not 3000)
kubectl -n monitoring port-forward svc/kube-prom-prometheus 9090:9090
# in Prometheus, query:  DCGM_FI_DEV_GPU_UTIL   (needs platform/10-gpu installed)
```

> **Grafana is on port 3001, not the usual 3000.** Port 3000 is intentionally
> left free so the lab can run next to another local app that uses it.

## How the Prometheus Operator finds things (under the hood)

You don't edit `prometheus.yml`. Instead, CRDs declare *intent* and the operator
reconciles the scrape config:

- **ServiceMonitor / PodMonitor** — "scrape endpoints matching this selector."
- **PrometheusRule** — recording + alerting rules.
- The operator only picks up objects whose labels match the Prometheus's
  `ruleSelector` / `serviceMonitorSelector`. In this lab that selector is
  `release: kube-prom`, so **every** SM/rule carries that label. Forgetting it is
  the #1 "my metrics/alerts don't show up" cause.

Scrape path for GPUs: `dcgm-exporter` Service → ServiceMonitor (`release:
kube-prom`) → Prometheus TSDB → PromQL → Grafana panels + alerts.

## DCGM field reference (the ones that matter)

| Metric | Meaning | Use |
|--------|---------|-----|
| `DCGM_FI_DEV_GPU_UTIL` | % time the GPU had ≥1 kernel running | "is the GPU busy at all?" |
| `DCGM_FI_PROF_PIPE_TENSOR_ACTIVE` | fraction of cycles tensor cores active | "is it using tensor cores (fp16/bf16)?" |
| `DCGM_FI_DEV_FB_USED` / `DCGM_FI_DEV_FB_FREE` | framebuffer (VRAM) used/free (MiB) | VRAM pressure → CUDA-OOM risk |
| `DCGM_FI_DEV_POWER_USAGE` | watts | throttling / efficiency |
| `DCGM_FI_DEV_GPU_TEMP` | °C | thermal throttling |
| `DCGM_FI_DEV_XID_ERRORS` | driver/HW fault codes | hardware health, cordon triggers |
| `DCGM_FI_PROF_DRAM_ACTIVE` | memory-bandwidth activity | memory-bound vs compute-bound |

## The interview headline: I/O-bound vs tensor-core-underutilized

> *"How do you tell whether a slow training run is bottlenecked on network/storage
> I/O or on the GPU not using its tensor cores?"*

Read the DCGM metrics together, not `GPU_UTIL` alone:

- **`GPU_UTIL` low** (e.g. 20%) → the GPU is *idle waiting for data*. The
  bottleneck is upstream: dataloader, storage/PVC throughput, or network (the
  AllReduce / shard fetch). Confirm with `iperf3` (East-West bandwidth) and
  storage latency. `GPU_UTIL` is a coarse "something ran" gauge — high ≠ efficient.
- **`GPU_UTIL` high but `PROF_PIPE_TENSOR_ACTIVE` low** → the GPU is busy but
  *not* using tensor cores: wrong dtype (fp32 instead of fp16/bf16), un-fused
  ops, or a memory-bound kernel. That's a model/framework fix, not an infra fix.
- **`FB_USED` near capacity** → you're one batch away from CUDA OOM (see
  `scenarios/b-vram-oom`), which K8s won't catch — hence the `GPUVRAMNearExhaustion`
  alert here.

That single answer — reading `GPU_UTIL` + `TENSOR_ACTIVE` + `FB_USED` together —
is exactly the "beyond naming tools, explain how it works" depth the JD wants.

## Files

| File | Purpose |
|------|---------|
| `kube-prometheus-stack-values.yaml` | slim Prometheus/Grafana profile for 8 GB |
| `dcgm-servicemonitor.yaml` | scrape the (fake) DCGM exporter |
| `grafana-dashboard-gpu.yaml` | auto-imported GPU dashboard (util/VRAM/tensor/power/temp) |
| `prometheusrule-gpu.yaml` | alerts mapped to the 3 failure scenarios |

## JD coverage
Observability, alerting, monitoring, cost/efficiency (idle-GPU detection), GPU
utilization understanding, and the ability to explain telemetry end-to-end.
