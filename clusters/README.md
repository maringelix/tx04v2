# clusters/ — the cluster substrate (kind + KWOK)

> **Docker-only:** use `./lab.sh ...` or `.\lab.ps1 ...` from the repository
> root. Do not install kind, kubectl, Helm or Bash on the host. Any raw
> `kubectl` shown below means `./lab.sh kubectl` (or `.\lab.ps1 kubectl`).

This module gives the lab a **real Kubernetes control plane** with a **handful of
real nodes** (kind) and then **hundreds of fake nodes** (KWOK) so you can
demonstrate large-scale scheduling on a laptop.

```
                         HOST (Windows + Docker Desktop, ~8 GB)
 ┌───────────────────────────────────────────────────────────────────────┐
 │  kind cluster "tx04v2"  (each node = a Docker container)                 │
 │                                                                         │
 │   control-plane          worker (gpu pool)        worker (cpu pool)     │
 │   ┌───────────────┐      ┌────────────────┐       ┌────────────────┐   │
 │   │ apiserver     │      │ kubelet        │       │ kubelet        │   │
 │   │ etcd          │      │ containerd     │       │ containerd     │   │
 │   │ scheduler     │      │ label:         │       │ label:         │   │
 │   │ controllers   │      │  gpu.present   │       │  pool=cpu      │   │
 │   └───────────────┘      │  run.ai/...    │       └────────────────┘   │
 │                          └────────────────┘                            │
 │                                                                         │
 │   + KWOK fake fleet:  kwok-gpu-0001 .. kwok-gpu-0100  (8 GPUs each)     │
 │     (no kubelet, no containers — the kwok-controller fakes them)        │
 └───────────────────────────────────────────────────────────────────────┘
```

## What is real vs. simulated

| Layer | Real? | Notes |
|-------|-------|-------|
| api-server, etcd, **kube-scheduler**, controller-manager | ✅ real | scheduling decisions are genuine |
| kind worker nodes (kubelet + containerd) | ✅ real | 2 nodes; actually run containers |
| KWOK nodes (kubelet + runtime) | ❌ faked | `kwok-controller` writes their heartbeat/status; **no containers run** |
| GPUs | ❌ faked | advertised as the `nvidia.com/gpu` extended resource (see `platform/10-gpu`) |

**Why this matters for the JD:** the requirement is "large-scale K8s — hundreds of
nodes, tens of clusters." KWOK lets you *actually schedule 400–900 GPU pods across
100 nodes* and watch the real scheduler's binpack/spread/pending behavior — the
control plane can't tell the nodes are fake.

## Files

| File | Purpose |
|------|---------|
| `kind/kind-cluster.yaml` | Default cluster: 1 control-plane + 2 workers, kindnet CNI, kube-proxy. Boots on ~8 GB. |
| `kind/kind-cluster-cilium.yaml` | CNI variant: `disableDefaultCNI` + `kubeProxyMode: none` for the Cilium/eBPF module. |
| `kwok/install.sh` | Installs the KWOK controller (in-cluster mode) + fast Stages. |
| `kwok/fake-gpu-node.yaml` | Template for one fake 8-GPU node. |
| `kwok/create-fake-nodes.sh` | Stamps out N fake nodes (`bash create-fake-nodes.sh 100`). |
| `kwok/scale-workload.yaml` | 400 single-GPU pods to exercise the scheduler at scale. |

## Quickstart

```powershell
.\lab.ps1 up
.\lab.ps1 kwok 100
.\lab.ps1 scale
.\lab.ps1 kubectl get pods -n kwok-scale -o wide
.\lab.ps1 down
```

### Cilium variant

```powershell
.\lab.ps1 up-cilium
```

## Talking points

- **kind node = container:** a kind "node" is a Docker container running systemd +
  containerd + kubelet, joined by kubeadm. There's no VM. Great for a faithful
  control plane; useless for real GPUs (hence the fake-gpu-operator).
- **Node labels must be set at kubelet registration** (`kubeadmConfigPatches` →
  `node-labels`). Labels applied later via `kubectl label` survive, but the ones a
  controller keys off at join time (like our GPU pool label) belong in the kubelet
  args so they're present from the first heartbeat.
- **KWOK vs kubemark:** both simulate nodes; KWOK is lighter (single controller,
  CRD-driven Stages) and is the modern default for scheduler/scale testing.
- **Extended-resource scheduling is a hard gate:** once `nvidia.com/gpu` requests
  exceed cluster capacity, pods sit `Pending` with `Insufficient nvidia.com/gpu` —
  this is exactly where Cluster Autoscaler / Karpenter would add GPU nodes.
