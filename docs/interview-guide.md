# Interview guide — Kubernetes GPU / AI-compute platform

Prep for a hands-on, "explain how it works under the hood" IC interview. Built
around this lab so every answer maps to something you actually ran.

> How to use it: skim the pitch, drill the themed Q&A, memorize the rapid-fire
> table, and be able to tell the three war stories cold. The interviewers reward
> **mechanism + a real example + the tradeoff**, not tool name-dropping.

---

## 1. 60-second project pitch (STAR)

> "To go deep on AI-platform operations I built **tx04v2**, a lab that simulates a
> GPU compute platform on Kubernetes. I run a multi-node **kind** cluster and use
> **KWOK** to scale it to hundreds of fake GPU nodes so I can exercise the real
> scheduler at fleet scale on a laptop. GPUs are simulated with the
> **fake-gpu-operator**, which advertises the `nvidia.com/gpu` resource and emits
> the same **DCGM** telemetry a real cluster would. On top I run **Volcano** for
> gang scheduling of distributed training, a vLLM-style server autoscaled on
> **in-flight requests** via the HPA + prometheus-adapter, **Cilium/eBPF** for
> networking with NodeLocal DNSCache and conntrack tuning, and a
> **Prometheus/Grafana/DCGM** observability stack. Then I deliberately break it:
> multi-GB image pulls causing ImagePullBackOff/DiskPressure, silent **CUDA VRAM
> OOMs** that never trip OOMKilled, and DNS/conntrack saturation from distributed
> jobs — each with a root-cause runbook and a durable fix. The point was to be
> able to explain, end to end, how compute, scheduling, networking, DNS and GPU
> telemetry actually fit together in production."

Shorter version (15s): *"I built a Kubernetes GPU-platform lab — fake GPUs +
DCGM, Volcano gang scheduling, vLLM autoscaling, Cilium/eBPF, and three
production failure-scenario runbooks — to practice operating AI infra at scale
and explaining it under the hood."*

---

## 2. Themed Q&A

### Kubernetes fundamentals & architecture
- **Q: Walk me through what happens from `kubectl apply` to a running pod.**
  A: api-server (authN → RBAC → admission webhooks) persists to etcd →
  kube-scheduler Filters/Scores a node and writes a Binding → the node's kubelet
  pulls images (CRI/containerd), sets up the network (CNI), for GPUs calls the
  device-plugin `Allocate`, and starts containers → kube-proxy/Cilium program
  Service routing. (See `docs/under-the-hood.md §1`.)
- **Q: requests vs limits?** A: requests drive **scheduling** (guaranteed, count
  against node allocatable) and set the cgroup floor; limits are the **cap**. CPU
  over-limit → throttled; memory over-limit → **OOMKilled (137)**. GPUs: requests
  must equal limits (no overcommit).
- **Q: How does RBAC work?** A: Subjects (user/group/ServiceAccount) bound via
  RoleBinding/ClusterRoleBinding to Roles/ClusterRoles that allow verbs on
  resources. Least-privilege; ServiceAccount tokens are projected into pods.
- **Q: Readiness vs liveness vs startup probes?** A: readiness gates traffic
  (removed from Endpoints when failing), liveness restarts a wedged container,
  startup protects slow-booting apps from premature liveness kills.

### GPU scheduling & device plugins
- **Q: How does Kubernetes know about GPUs?** A: the device plugin registers over
  a Unix socket and `ListAndWatch` reports device IDs → kubelet sets
  `nvidia.com/gpu` capacity; `Allocate` injects `/dev/nvidia*` + env at pod start.
- **Q: Why can't you overcommit a GPU like CPU?** A: it's an extended resource —
  integer, requests==limits, no compressible time-share by default. Sharing needs
  time-slicing/MPS/MIG, which redefine what one unit means.
- **Q: time-slicing vs MPS vs MIG?** A: time-slicing = cooperative context switch,
  no isolation; MPS = process-level, soft; **MIG = hardware partitions with
  dedicated VRAM+SMs**. Pick MIG for multi-tenant/VRAM-bounded inference,
  time-slicing for bursty dev/CI.
- **Q: How do you keep non-GPU pods off GPU nodes?** A: taint GPU nodes
  (`nvidia.com/gpu:NoSchedule`) + tolerations on GPU workloads, plus nodeSelector/
  affinity on the GPU product label.

### Distributed training & gang scheduling
- **Q: Why does distributed training need gang scheduling?** A: synchronous
  data-parallel training barriers on AllReduce every step; if only some workers
  start they block and burn GPU time, and two half-scheduled jobs deadlock on
  fragmented GPUs. Volcano's PodGroup `minMember` makes the job atomic.
- **Q: Volcano vs default scheduler vs Kueue vs Training Operator?** A: default =
  no gang; Volcano = gang+queues+binpack+preemption; Kueue = quota/queueing on top
  of the default scheduler; Training Operator = the job CRDs (PyTorchJob/MPIJob)
  that create pods — pair it with Volcano/Kueue for the gang.
- **Q: binpack vs spread for GPUs?** A: binpack packs GPUs densely to keep whole
  nodes free for the next big gang (less fragmentation); spread favors HA for
  inference replicas.

### Serving & autoscaling
- **Q: What do you autoscale LLM inference on?** A: **concurrency / queue depth**
  (`num_requests_running`/`waiting`), not CPU — CPU is idle while the GPU is busy.
  Wire it via HPA + prometheus-adapter (custom.metrics) or KEDA (external.metrics,
  scale-to-zero).
- **Q: HPA vs VPA vs Cluster Autoscaler vs Karpenter?** A: replicas / pod-requests
  / node-count (per node group) / node-count (just-in-time, instance-flexible).
  They compose: HPA adds pods → Pending (Insufficient GPU) → CA/Karpenter adds GPU
  nodes.
- **Q: Why is GPU autoscaling hard?** A: cold start = schedule onto a GPU node
  (maybe provisioned first) + pull a multi-GB image + load weights into VRAM =
  minutes. Mitigate with warm pools, image pre-pull, weight caching, and
  scale-to-zero for spiky traffic.
- **Q: What actually fills VRAM at inference?** A: the **KV-cache** (grows with
  batch × context length) plus weights; vLLM's PagedAttention manages it.

### Networking, eBPF, DNS
- **Q: Why Cilium/eBPF over iptables kube-proxy?** A: eBPF does Service LB/policy
  as O(1) map lookups at socket/tc hooks instead of walking iptables chains that
  grow with #Services — big win for high pod-to-pod fan-out (AllReduce). Plus L7
  policy + Hubble.
- **Q: Explain the ndots:5 problem.** A: names with <5 dots are tried against every
  search domain first, so one external lookup becomes ~5 queries → thousands of
  workers DDoS CoreDNS. Fix: ndots:1 / FQDNs + NodeLocal DNSCache.
- **Q: conntrack table full — what and why?** A: one entry per flow; distributed
  workers + DNS churn exhaust `nf_conntrack_max` → dropped packets → "flaky
  network." Raise max, shorten timeouts, TCP DNS, eBPF.
- **Q: Most common NetworkPolicy outage?** A: default-deny egress with no DNS
  allow rule → everything fails to resolve.

### Observability & DCGM
- **Q: How do you tell if a slow training run is I/O-bound or tensor-core-
  underutilized?** A (the money answer): read DCGM together — `GPU_UTIL` low →
  data-starved (dataloader/storage/network, confirm with iperf3); `GPU_UTIL` high
  but `PROF_PIPE_TENSOR_ACTIVE` low → busy but not using tensor cores (wrong dtype
  / unfused kernels); `FB_USED` near capacity → CUDA-OOM risk. `GPU_UTIL` alone
  lies.
- **Q: How does Prometheus find targets?** A: Operator CRDs — ServiceMonitor/
  PodMonitor/PrometheusRule selected by label (here `release: kube-prom`). Forget
  the label → silently no scraping.
- **Q: RED vs USE?** A: RED (Rate/Errors/Duration) for request-driven services;
  USE (Utilization/Saturation/Errors) for resources like GPUs/nodes.

### Cloud / IaaS depth (AWS/GCP/Azure)
- **Q: How do managed GPU clusters (EKS/GKE/AKS) get GPUs?** A: GPU node
  groups/pools with the right instance types + the NVIDIA device plugin/GPU
  operator (often via an add-on); autoscaling via CA/Karpenter; spot/preemptible
  for cost.
- **Q: How do pods get cloud identity without static keys?** A: **IRSA** (EKS) /
  **Workload Identity** (GKE) / **Workload Identity** (AKS) — federate the pod's
  ServiceAccount to a cloud IAM role via OIDC.
- **Q: Storage for ML?** A: fast scratch (local NVMe / instance store) for
  datasets/checkpoints, object store (S3/GCS) for weights, RWX (EFS/Filestore) or
  a parallel FS (Lustre/FSx) for shared data; separate weights from images.
- **Q: How does a Service reach the internet / get reached?** A: egress via NAT
  gateway; ingress via LoadBalancer Service → cloud LB, or Ingress/Gateway API →
  controller → Services → pod IPs (CNI). DNS via CoreDNS internally + cloud DNS
  externally.

### Large-scale operations
- **Q: How would you operate hundreds of nodes / tens of clusters?** A: GitOps
  (Argo/Flux) for config, fleet management, standardized node images, autoscaling,
  SLOs + alerting, progressive rollout, and blast-radius isolation per cluster.
  In the lab, KWOK lets me test scheduler/quota behavior at that node count.
- **Q: A whole GPU node goes bad — how do you catch it?** A: DCGM XID errors +
  node conditions → automatic cordon/drain (node-problem-detector /
  descheduler), then repair/replace; gang jobs restart as a group.

### Security & RBAC
- Least-privilege RBAC, per-namespace isolation, Pod Security Standards, image
  provenance/signing, NetworkPolicy default-deny, secrets via external stores,
  no static cloud keys (workload identity).

---

## 3. "Explain end-to-end" set
Be ready to whiteboard any of these (all detailed in `docs/under-the-hood.md`):
1. `kubectl apply` → running pod.
2. Pod-to-pod packet path (veth → conntrack → Service LB → peer), iptables vs eBPF.
3. DNS resolution for `mysvc` incl. ndots + search domains.
4. GPU pod scheduling + the device-plugin `Allocate` flow.
5. The HPA control loop and the custom-metrics pipeline.
6. How AllReduce stresses network bandwidth + conntrack.

---

## 4. War stories (tell these as STAR)
Each has a full runbook under `scenarios/`.

- **A — Image/storage:** *10-GB CUDA images → ImagePullBackOff + DiskPressure
  evictions.* Root cause: cold-node serial pulls, no cache. Fix: node pre-pull +
  SOCI lazy pulling + weights-out-of-image; added ImagePullBackOff/DiskPressure
  alerts. (`scenarios/a-image-storage`)
- **B — Silent VRAM OOM:** *GPU pod CrashLoopBackOff, no OOMKilled, dashboards
  green.* Root cause: CUDA OOM is in-process (exit 1); no cgroup for VRAM. Fix:
  DCGM `FB_USED` alert + MIG to bound VRAM + batch/checkpointing guidance.
  (`scenarios/b-vram-oom`)
- **C — DNS/conntrack at scale:** *Distributed job → cluster-wide SERVFAIL +
  random timeouts.* Root cause: ndots:5 ~5x amplification saturating CoreDNS +
  conntrack exhaustion. Fix: NodeLocal DNSCache + ndots:1 + scale CoreDNS + raise
  conntrack; added SERVFAIL/conntrack alerts. (`scenarios/c-dns-conntrack`)

---

## 5. Rapid-fire (one-line answers)

| Q | A |
|---|---|
| exit 137 vs exit 1 | 137 = SIGKILL/OOMKilled (host RAM cgroup); 1 = app error (e.g. CUDA OOM) |
| OOMKilled vs CUDA OOM | kernel kills container (K8s-visible) vs in-process VRAM failure (K8s-blind) |
| requests vs limits | requests = schedule/guarantee; limits = cap (mem over = OOMKilled) |
| GPU requests==limits? | yes — integer extended resource, no overcommit |
| time-slicing vs MIG | cooperative no-isolation vs hardware VRAM/compute partition |
| ndots:5 | sub-5-dot names tried against search domains first → amplification |
| conntrack full | table at `nf_conntrack_max` → kernel drops packets |
| ClusterIP/NodePort/LoadBalancer | internal VIP / node port / external cloud LB |
| HPA/VPA/CA/Karpenter | replicas / requests / node group / just-in-time nodes |
| gang scheduling | all-or-nothing pod group (PodGroup minMember) |
| DCGM_FI_DEV_GPU_UTIL | % time ≥1 kernel ran (busy ≠ efficient) |
| PROF_PIPE_TENSOR_ACTIVE | tensor-core cycle fraction (dtype/efficiency signal) |
| FB_USED | VRAM used — VRAM pressure / OOM risk |
| kube-proxy replacement | Cilium eBPF does Service LB instead of iptables/ipvs |
| NodeLocal DNSCache | per-node DNS cache; offloads CoreDNS, TCP forward |
| KWOK | fake nodes (no kubelet) for scale testing |
| KServe / vLLM / KEDA | serving CRD / LLM engine / event autoscaler (scale-to-zero) |
| binpack vs spread | dense GPU packing vs HA distribution |
| Workload Identity/IRSA | pod SA → cloud IAM via OIDC (no static keys) |

---

## 6. Questions to ask the interviewer
- What's the GPU fleet size / mix (A100/H100, MIG?) and biggest scaling pain?
- Single mega-cluster or many clusters — and how do you manage fleet config?
- Which scheduler stack — Volcano/Kueue/Run:ai — and how is multi-tenancy/fairness
  handled?
- Training vs inference split; do you scale-to-zero inference?
- Top recurring production incident on the platform today?
- CNI + how you handle East-West bandwidth for NCCL (RDMA/GPUDirect?).
- On-call model and what "good" looks like in 6 months for this role.
