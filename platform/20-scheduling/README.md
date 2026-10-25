# platform/20-scheduling — batch & gang scheduling with Volcano

> **Docker-only:** run with `.\lab.ps1 scheduling` or `./lab.sh scheduling`.
> Raw kubectl examples execute through the launcher, never a host installation.

The default `kube-scheduler` binds pods **one at a time** and has no concept of a
group. That's fine for microservices and fatal for distributed training. This
module installs [Volcano](https://volcano.sh) to add **gang (all-or-nothing)
scheduling**, queues, fair-share, binpack and preemption.

## Install & demo

```bash
bash platform/20-scheduling/install.sh          # Volcano + the "ml" queue
kubectl apply -f platform/20-scheduling/gang-training-job.yaml
kubectl get podgroups,pods -n ml-jobs -w        # 4 pods start together, or not at all

# contrast: the no-gang anti-pattern
kubectl apply -f platform/20-scheduling/deadlock-demo.yaml
kubectl get pods -n ml-jobs -l demo=deadlock -o wide   # 8 GPUs held, neither job complete
kubectl delete -f platform/20-scheduling/deadlock-demo.yaml
```

## Why distributed training needs gang scheduling

Synchronous data-parallel training runs an **AllReduce** collective every step to
average gradients across all workers. The collective is a barrier: it cannot
complete until **every** rank participates. So:

- If the scheduler starts 3 of 4 workers (because only 3 GPUs were free), those 3
  immediately **block** at the first AllReduce waiting for rank 4 — burning GPU
  time doing nothing.
- Worse, two competing jobs each grab a fraction of the GPUs and **neither** can
  reach its required size: a **fragmentation deadlock** (`deadlock-demo.yaml`).

Gang scheduling makes the job **atomic**: Volcano creates a `PodGroup` with
`minMember = N` and only binds pods once all N can be placed. Fewer than N free →
the whole group waits. This both prevents deadlock and stops idle-GPU burn.

## Key concepts (talking points)

- **PodGroup / minMember (`minAvailable`)** — the gang. The `gang` plugin enforces
  it; `job.spec.minAvailable` on a Volcano Job maps to `PodGroup.spec.minMember`.
- **Queues + DRF/proportion** — multi-tenant fairness. `weight` sets relative
  share; `capability` sets a hard cap. Dominant Resource Fairness balances across
  heterogeneous requests (GPU vs CPU vs memory).
- **binpack vs spread** — binpack **densely packs** GPUs to keep whole nodes free
  for the next big gang (less fragmentation, better for training); spread favors
  HA (better for inference replicas). Volcano's `binpack` plugin vs the default
  scheduler's least-allocated scoring.
- **Preemption & reclaim** — a higher-priority training job can preempt lower-
  priority pods; `reclaimable` queues lend idle capacity and take it back.
- **Topology / NUMA / GPU affinity** — for multi-GPU nodes, co-locating a job's
  ranks on GPUs sharing NVLink/PCIe dramatically speeds NCCL AllReduce. This is
  where topology-aware scheduling matters.

## When to use what

| Tool | Role |
|------|------|
| **kube-scheduler** (default) | services, single-pod jobs; no gang |
| **Volcano** | gang scheduling, queues, fair-share, binpack, preemption — batch/AI |
| **Kueue** | queueing/quota layer on top of the default scheduler (lighter, GA in many managed clusters) |
| **Kubeflow Training Operator** | job *CRDs* (PyTorchJob/MPIJob/TFJob) that create the pods; pair with Volcano/Kueue for the gang |

## JD coverage
Autoscaling & scheduling at scale; supporting ML/GPU workloads; explaining *why*
distributed systems behave the way they do; durable design (deadlock prevention).
