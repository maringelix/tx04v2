# Scenario B — the silent GPU VRAM OOM (CUDA OOM ≠ OOMKilled)

> Run scripts inside the toolbox, for example
> `.\lab.ps1 run bash scenarios/b-vram-oom/break.sh`. Raw kubectl examples go
> through `.\lab.ps1 kubectl`; nothing is installed on the host.

The single most-misdiagnosed GPU failure. **Runbook:** Symptom → Triage → Root
cause → Fix → Prevention.

```bash
bash scenarios/b-vram-oom/break.sh    # runs BOTH: cuda-oom-sim + host-oom
# ...triage & compare...
bash scenarios/b-vram-oom/fix.sh
```

## Symptom
A training/inference pod is in `CrashLoopBackOff`. `kubectl get pods` shows
restarts climbing. Host-RAM dashboards and `kubectl top pod` look **fine**. No
`OOMKilled`. On-call is baffled: "nothing shows a memory problem."

## Triage
```bash
kubectl -n ml-jobs logs cuda-oom-sim --previous | tail        # the truth is here
# -> "torch.cuda.OutOfMemoryError: CUDA out of memory. Tried to allocate ..."
kubectl -n ml-jobs get pod cuda-oom-sim \
  -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason} exit={.status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}'
# -> "Error exit=1"   (NOT OOMKilled, NOT 137)
# On a real GPU:  nvidia-smi   (see near-100% memory)  +  DCGM_FI_DEV_FB_USED
```

## Root cause
GPU VRAM (framebuffer) lives on the device behind the driver. **There is no cgroup
controller for VRAM**, so:
- the Linux OOM killer never fires (it only guards host RAM);
- `cudaMalloc` fails inside the process → PyTorch raises `CUDA out of memory` →
  the interpreter exits **1** → container restarts → `CrashLoopBackOff`;
- Kubernetes sees a generic app crash, not a memory event.

## Host RAM OOM vs GPU VRAM OOM

| | Host RAM OOM | GPU VRAM OOM |
|--|--------------|--------------|
| Killed by | Linux kernel cgroup OOM killer | nobody — the process aborts itself |
| Pod reason | `OOMKilled` | *(generic)* — no special reason |
| Exit code | **137** (128 + SIGKILL) | **1** (app error) |
| K8s-visible? | ✅ yes (events, metrics) | ❌ no |
| Detect with | `kubectl`, kube-state-metrics | **DCGM** `FB_USED`, app logs |
| Fix lever | `resources.limits.memory`, VPA | batch size, MIG, checkpointing |

## Fix
1. **Detect via DCGM**, not cgroups: alert on `FB_USED/(FB_USED+FB_FREE) > 0.9`
   (`GPUVRAMNearExhaustion` in `platform/50-observability`), and scrape the app's
   CUDA-OOM log line into an event/metric.
2. **Bound VRAM** with MIG or a fractional-GPU scheduler (isolation between jobs).
3. **Tune** the workload: batch size, gradient/activation checkpointing,
   `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`, mixed precision.

## Prevention
- Ship the DCGM VRAM alert by default; dashboard `FB_USED` next to `GPU_UTIL`.
- Treat "CrashLoopBackOff on a GPU pod with exit 1" as *VRAM-first* in the
  runbook — check `logs --previous` and DCGM before anything else.

## One-line interview version
> "A trainer was CrashLoopBackOff-ing but nothing showed OOMKilled — because a
> CUDA OOM crashes the process (exit 1), and there's no cgroup for VRAM so
> Kubernetes is blind to it. I proved it from `logs --previous` and DCGM
> `FB_USED`, then made it durable: a DCGM VRAM alert, MIG to bound per-job VRAM,
> and batch-size/checkpointing guidance for the ML team."
