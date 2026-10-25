# platform/10-gpu — GPU enablement (device plugin + DCGM), simulated

> **Docker-only:** run with `.\lab.ps1 gpu` or `./lab.sh gpu`. Prefix raw
> kubectl commands with the launcher; never install kubectl or Helm on the host.

Makes Kubernetes **see and schedule GPUs** without any real hardware, using
[`run-ai/fake-gpu-operator`](https://github.com/run-ai/fake-gpu-operator). This is
the foundation every other module builds on.

## Install

```bash
bash platform/10-gpu/install.sh
# verify
kubectl get nodes -o custom-columns=NODE:.metadata.name,GPU:.status.allocatable.nvidia\\.com/gpu
kubectl apply -f platform/10-gpu/sample-gpu-pod.yaml
kubectl get pods -o wide          # gpu-smoke Running, gpu-too-big Pending
kubectl exec -it gpu-smoke -- nvidia-smi
```

Raw helm (PowerShell-friendly):

```bash
helm upgrade --install gpu-operator oci://ghcr.io/run-ai/fake-gpu-operator/fake-gpu-operator \
  -n gpu-operator --create-namespace --version 0.1.0 \
  -f platform/10-gpu/fake-gpu-operator-values.yaml --wait
```

## How GPUs actually get into a pod (under the hood)

1. **Device plugin registration.** The device plugin runs as a DaemonSet on GPU
   nodes and registers with the kubelet over a Unix socket
   (`/var/lib/kubelet/device-plugins/`). It implements a gRPC service:
   - `ListAndWatch` — streams the list of healthy device IDs to the kubelet. The
     kubelet turns the count into `node.status.capacity["nvidia.com/gpu"]`.
   - `Allocate` — called when a pod is admitted; returns the device mounts / env
     (`NVIDIA_VISIBLE_DEVICES`, `/dev/nvidia*`) to inject into the container.
2. **Scheduling.** `nvidia.com/gpu` is an **extended resource**. The scheduler
   treats it like cpu/memory in Filter (does the node have a free GPU?) and Score,
   but with two rules: it's **integer-only** and **requests must equal limits**
   (no overcommit, no fractions — a fractional GPU only exists via time-slicing/
   MIG, which change what one "unit" means).
3. **Binding + Allocate.** Scheduler binds the pod; the kubelet calls the plugin's
   `Allocate`, injects the device, and starts the container. `nvidia-smi` inside
   now sees exactly the GPUs it was granted.

The fake operator reproduces steps 1–3 in software: it patches node capacity,
answers the device-plugin API, and its admission webhook injects a fake
`nvidia-smi`. The scheduler cannot tell the difference — which is the whole point.

## Why the abstractions matter (talking points)

- **A GPU is not like CPU.** CPU is compressible and overcommittable (millicores,
  throttling). A GPU request is a *whole device* (or a fixed slice). You cannot
  "burst" a GPU; capacity is a hard gate → `Insufficient nvidia.com/gpu` Pending.
- **VRAM is invisible to Kubernetes.** The `nvidia.com/gpu` count says nothing
  about framebuffer. There is no cgroup for VRAM, so K8s can neither limit nor
  observe it — this is the root of the silent CUDA-OOM in `scenarios/b-vram-oom`.
- **Sharing = time-slicing vs MPS vs MIG** (see `real-hardware/`): only MIG gives
  hardware VRAM+compute isolation; time-slicing multiplexes compute with zero
  isolation. Choose per workload: MIG for multi-tenant inference, time-slicing for
  bursty dev/CI.
- **DCGM is your GPU truth source.** The device plugin only tells you *counts*.
  Utilization, VRAM used, tensor-core activity, temperature, power and XID errors
  come from **DCGM** (`dcgm-exporter`), scraped by Prometheus in
  `platform/50-observability`. "Is the GPU busy?" is a DCGM question, not a
  kubelet question.
- **Placement controls:** GPU nodes are typically **tainted** (`nvidia.com/gpu`)
  so only GPU workloads (with a matching toleration) land there, plus
  nodeSelector/affinity on the GPU product label for "give me an A100, not a T4."

## JD coverage
Deep K8s architecture (extended resources, device-plugin API, scheduling);
GPU fleet capability; explaining "how compute connects" under the hood; ties
directly into observability (DCGM) and the VRAM-OOM troubleshooting scenario.
