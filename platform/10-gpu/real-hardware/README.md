# Real-hardware notes (not used by the CPU-only lab)

This folder documents what changes when there is an actual NVIDIA GPU under the
node. Nothing here is applied by the lab — the lab uses `fake-gpu-operator`.

## The NVIDIA software stack, bottom to top

| Layer | What it does |
|-------|--------------|
| **GPU driver** (kernel module) | talks to the hardware; exposes `/dev/nvidia*` |
| **NVIDIA Container Toolkit** | lets containerd/CRI inject the driver + `/dev/nvidia*` into a container (`nvidia` runtime class) |
| **k8s-device-plugin** | speaks the kubelet device-plugin gRPC API; advertises `nvidia.com/gpu`; performs `Allocate` |
| **DCGM + dcgm-exporter** | reads GPU telemetry (util, VRAM, tensor activity, temp, power, XID) and exports Prometheus metrics |
| **GPU Operator** | Helm-managed umbrella that installs/updates all of the above + node feature discovery |

## GPU sharing options

| Mechanism | Isolation | VRAM partitioned? | Use case |
|-----------|-----------|-------------------|----------|
| **Time-slicing** | none (cooperative context switch) | ❌ no | bursty dev/CI, oversubscription |
| **MPS** (Multi-Process Service) | process-level | ❌ no (soft limits) | cooperative same-tenant jobs |
| **MIG** (Multi-Instance GPU) | hardware | ✅ yes | multi-tenant, VRAM-bounded inference |

The lab's `fake-gpu-operator` reproduces the *scheduling* surface (the
`nvidia.com/gpu` resource and DCGM metrics) so you can practice everything except
the parts that need silicon. See `nvidia-device-plugin-timeslicing.yaml` for the
real time-slicing config.
