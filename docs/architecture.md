# tx04v2 architecture

tx04v2 simulates a **GPU AI-compute platform** on a laptop. Everything runs on CPU;
the GPU surface (the `nvidia.com/gpu` resource + DCGM telemetry) is faithfully
faked so the *platform engineering* is real even though no CUDA executes.

## Runtime boundary: Docker only

Docker Desktop is the sole host dependency. The repository builds a disposable
`tx04v2-toolbox:local` image containing kind, kubectl, Helm and Bash. `lab.ps1` or
`lab.sh` mounts the Docker socket so kind can create sibling node containers;
all cluster administration then runs from the toolbox on Docker's `kind`
network. The isolated kubeconfig and Helm state live under ignored `.state/`.
Nothing writes to the host's kubeconfig, CLI paths or package directories.

## The whole platform

```
                                 HOST (Windows + Docker Desktop, ~8 GB)
┌──────────────────────────────────────────────────────────────────────────────┐
│ kind cluster "tx04v2"                                                            │
│                                                                                │
│  CONTROL PLANE (real)                    NODES (real kind workers)             │
│  ┌───────────────────────┐   ┌──────────────────────┐  ┌───────────────────┐ │
│  │ api-server / etcd      │   │ worker: GPU pool     │  │ worker: CPU pool  │ │
│  │ kube-scheduler         │   │  fake-gpu-operator   │  │  monitoring/infra │ │
│  │ + Volcano scheduler    │   │  8x A100 (fake)      │  │                   │ │
│  │ controller-manager     │   │  dcgm-exporter(fake) │  │                   │ │
│  └───────────────────────┘   └──────────────────────┘  └───────────────────┘ │
│                                                                                │
│  KWOK fake fleet (scale):  kwok-gpu-0001 .. 0100  (8 GPUs each, no kubelet)    │
│                                                                                │
│  PLATFORM LAYERS                                                                │
│   10-gpu          nvidia.com/gpu + DCGM metrics                                 │
│   20-scheduling   Volcano gang scheduling + queues                             │
│   30-serving      mock-llm Deployment + HPA (concurrency) + loadgen            │
│   40-networking   Cilium/eBPF | NodeLocal DNSCache | conntrack | NetworkPolicy │
│   50-observability Prometheus + Grafana + DCGM dashboards + alerts             │
│                                                                                │
│  SCENARIOS (break/fix):  A image/storage   B VRAM-OOM   C DNS/conntrack        │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Control flow (how a GPU job runs)

1. `kubectl apply` a Volcano Job → api-server persists it in etcd.
2. Volcano controller creates a **PodGroup** (`minMember=N`) and the pods.
3. The **Volcano scheduler** gang-schedules: binds all N only if N GPUs are free,
   else the group waits (no partial start). Placement respects the
   `nvidia.com/gpu` resource + node labels/taints.
4. On each chosen node the **kubelet** calls the (fake) device plugin's `Allocate`
   and starts the container with the GPU "attached."
5. **DCGM exporter** publishes `DCGM_FI_DEV_*`; **Prometheus** scrapes it via a
   `ServiceMonitor`; **Grafana** and **alerts** consume it.

## Data flow (how a request is served)

`loadgen` → Service `mock-llm` (ClusterIP; kube-proxy iptables, or Cilium eBPF on
the cilium variant) → `mock-llm` pod. The pod's `/metrics` in-flight gauge is
scraped by Prometheus → `prometheus-adapter` exposes it on `custom.metrics.k8s.io`
→ the **HPA** scales replicas on concurrency.

## Simulated vs. real boundary

| Concern | In tx04v2 | On real hardware |
|---------|---------|------------------|
| Control plane, scheduler | real | real |
| Node kubelet (kind) | real | real |
| Node kubelet (KWOK) | faked | real |
| GPUs | faked (`fake-gpu-operator`) | driver + `k8s-device-plugin` |
| DCGM metrics | faked, same series | real `dcgm-exporter` |
| CNI, DNS, conntrack, Prometheus | real | real |

## Module → JD requirement map

| Module / doc | JD requirement it demonstrates |
|--------------|-------------------------------|
| `clusters/` (kind + KWOK) | large-scale K8s (hundreds of nodes), cluster health |
| `platform/10-gpu` | GPU platform, device plugins, extended resources |
| `platform/20-scheduling` | scheduling/autoscaling, distributed ML, durable design |
| `platform/30-serving` | autoscaling, DX, cost, LLM serving fundamentals |
| `platform/40-networking` | networking, DNS, eBPF, "how components connect" |
| `platform/50-observability` | observability, alerting, GPU utilization, efficiency |
| `scenarios/*` | structured troubleshooting, RCA, preventative remediation |
| `docs/interview-guide.md` | communication — explaining tradeoffs, risks, mechanisms |
