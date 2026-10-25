# Glossary

**AllReduce** — collective that sums/averages a tensor across all workers and
gives every worker the result; the per-step gradient sync in data-parallel
training. Bandwidth-bound and a barrier (needs all ranks).

**Binpack** — scheduling policy that packs pods densely onto few nodes (keeps
whole GPU nodes free for the next big gang); opposite of spread.

**cgroup** — Linux kernel mechanism that limits/accounts a process group's CPU,
memory, etc. Container `resources.limits` map to cgroups. **No cgroup for GPU VRAM.**

**CNI** — Container Network Interface; the plugin that wires pod networking
(kindnet, Calico, Cilium).

**conntrack** — netfilter connection tracking table; one entry per flow. Fills
under high connection churn → dropped packets.

**Continuous batching** — LLM serving technique (vLLM) that adds/removes requests
from the running batch each decode step to keep the GPU busy.

**CUDA OOM** — GPU VRAM exhaustion; fails in-process (exit 1), invisible to K8s.
Distinct from **OOMKilled**.

**DCGM** — NVIDIA Data Center GPU Manager; source of GPU telemetry
(`DCGM_FI_DEV_*`) exported to Prometheus by `dcgm-exporter`.

**Device plugin** — kubelet gRPC extension that advertises and allocates special
hardware (e.g. `nvidia.com/gpu`).

**DRF** — Dominant Resource Fairness; fair-shares heterogeneous requests across
queues (Volcano).

**eBPF** — run sandboxed programs in the Linux kernel; Cilium uses it for
networking/policy/observability without iptables.

**Extended resource** — a custom schedulable resource like `nvidia.com/gpu`;
integer-only, requests must equal limits, non-overcommittable.

**Framebuffer (FB)** — GPU VRAM. `DCGM_FI_DEV_FB_USED/FREE`.

**Gang scheduling** — all-or-nothing placement of a group of pods (a PodGroup);
prevents partial starts and deadlock in distributed training.

**HPA / VPA / Cluster Autoscaler / Karpenter** — scale replicas / scale pod
requests / add-remove nodes (CA, per node-group) / add-remove nodes (Karpenter,
just-in-time, instance-flexible).

**Hubble** — Cilium's flow-observability UI/CLI (L3/L4/L7 + DNS + drops).

**KServe** — CRD-based model serving (canary, scale-to-zero, autoscaling).

**KEDA** — event-driven autoscaler; enables scale-to-zero and queue-based scaling.

**kind** — Kubernetes IN Docker; each node is a container. Local clusters.

**KV-cache** — cached attention keys/values during LLM decode; usually the main
consumer of VRAM at inference.

**KWOK** — Kubernetes WithOut Kubelet; simulates many fake nodes for scale tests.

**MIG** — Multi-Instance GPU; hardware-partitions an A100/H100 into isolated
instances with dedicated VRAM + compute.

**MPS** — Multi-Process Service; process-level GPU sharing (soft isolation).

**NCCL** — NVIDIA Collective Communications Library; implements AllReduce etc.
over NVLink/PCIe/network.

**ndots** — resolv.conf option; names with fewer than `ndots` dots are tried
against search domains first (amplification risk; default 5 in clusters).

**NodeLocal DNSCache** — per-node DNS cache DaemonSet; offloads CoreDNS and cuts
tail latency + conntrack churn.

**OOMKilled** — kernel cgroup OOM kill of a container (host RAM); pod reason
`OOMKilled`, exit **137**.

**PagedAttention** — vLLM's paged VRAM management for the KV-cache (less
fragmentation).

**PodGroup** — Volcano CRD representing a gang; `minMember` is the gang size.

**Preemption** — evicting lower-priority pods to make room for higher-priority
ones.

**Queue** (Volcano) — multi-tenant capacity/fairness unit; `weight` + `capability`.

**ServiceMonitor / PodMonitor / PrometheusRule** — Prometheus Operator CRDs that
declare scrape targets and rules; selected by label (here `release: kube-prom`).

**SOCI / eStargz** — seekable image formats enabling lazy (on-demand) image
pulling so containers start before the full download.

**Taint / Toleration** — a node repels pods unless they tolerate the taint; used
to reserve GPU nodes for GPU workloads.

**Time-slicing** — cooperative GPU sharing via context switching; no VRAM/compute
isolation.

**Tensor core** — specialized matrix-multiply unit; low `TENSOR_ACTIVE` with high
`GPU_UTIL` means the GPU is busy but not using them (often wrong dtype).

**vLLM** — high-throughput LLM inference engine (continuous batching + PagedAttention).

**Volcano** — batch/AI scheduler adding gang scheduling, queues, fair-share,
binpack, preemption.

**XID error** — NVIDIA driver/hardware fault code (`DCGM_FI_DEV_XID_ERRORS`);
signals to cordon/investigate a node.
