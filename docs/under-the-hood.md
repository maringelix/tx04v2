# Under the hood — mechanisms behind the answers

Reference notes for the "explain how it actually works" parts of the interview.
Each section is deliberately mechanism-first.

## 1. From `kubectl apply` to a running pod
1. `kubectl` → **api-server**: authN (cert/token/OIDC) → authZ (RBAC) → admission
   (mutating then validating webhooks, e.g. defaults, Pod Security) → **etcd**.
2. **kube-scheduler** watches for pods with no `nodeName`. For each: **Filter**
   (predicates: resources incl. `nvidia.com/gpu`, nodeSelector/affinity,
   taints/tolerations, topology) → **Score** (least-allocated/spread, affinity) →
   pick highest → write a **Binding** (sets `nodeName`).
3. The node's **kubelet** sees the bound pod → calls the **CRI** (containerd) to
   pull images + create the sandbox → sets up networking via **CNI** → for GPUs
   calls the **device plugin** `Allocate` → starts containers → reports status.
4. **kube-proxy** (or Cilium eBPF) programs Service load-balancing so the pod is
   reachable via its Services.

## 2. Device plugin gRPC protocol (how a GPU is attached)
- The plugin registers with the kubelet on a Unix socket in
  `/var/lib/kubelet/device-plugins/`.
- `ListAndWatch` streams device IDs + health → kubelet sets
  `node.status.capacity["nvidia.com/gpu"]`.
- On pod admission, kubelet calls `Allocate(deviceIDs)` → plugin returns the
  device nodes (`/dev/nvidia*`), env (`NVIDIA_VISIBLE_DEVICES`), and mounts to
  inject. The container now sees exactly those GPUs.
- Extended resources are **integer, non-overcommittable**; requests must equal
  limits. Fractions only exist via time-slicing/MIG (which redefine one "unit").

## 3. CNI + the eBPF vs iptables datapath
- **Packet path:** pod → its `veth` → node netns → (routing/overlay) → peer node →
  `veth` → peer pod. Along the way: **conntrack** (state/NAT) and Service LB.
- **kube-proxy (iptables/ipvs):** Service→endpoint DNAT via iptables chains; long
  chains = per-packet cost that grows with #Services.
- **Cilium (eBPF):** programs attached at socket/tc hooks do Service LB and policy
  as O(1) map lookups — no chain walk. Lower latency/overhead under heavy
  pod-to-pod fan-out (AllReduce), plus L7 policy and Hubble flow visibility.

## 4. DNS resolution path (and the ndots trap)
- Pod `/etc/resolv.conf`: `nameserver <CoreDNS ClusterIP>`, a `search` list, and
  `options ndots:5`.
- A name with **< 5 dots** is tried against **every** search suffix first. So
  `api.github.com` → `.<ns>.svc.cluster.local`, `.svc.cluster.local`,
  `.cluster.local` (NXDOMAIN each), then the real query → ~4–5x amplification.
- **CoreDNS** resolves cluster names from its kubernetes plugin, forwards the rest
  upstream. **NodeLocal DNSCache** puts a cache on every node (169.254.20.10) so
  hits never hit CoreDNS and misses forward over TCP (less UDP conntrack churn).

## 5. Linux conntrack
- One entry per tracked flow; sized by `nf_conntrack_max`. Established/TIME_WAIT
  timeouts govern how long entries linger.
- Exhaustion → kernel drops packets + logs `nf_conntrack: table full, dropping
  packet` → app sees random timeouts. Distributed jobs + DNS storms fill it fast.
- Observe: `conntrack -S`, `/proc/sys/net/netfilter/nf_conntrack_count` vs `_max`,
  `dmesg`. Fix: raise max, shorten timeouts, TCP DNS, eBPF.

## 6. Image pull path
- kubelet → CRI `PullImage` → containerd resolves manifest → pulls layers → the
  **snapshotter** unpacks them into the rootfs. Big ML images = big pull + unpack
  + disk.
- **Lazy pulling** (SOCI / eStargz + Stargz snapshotter): mount the image and
  fetch layer contents on demand → the container starts before the full download.
- Node disk fills → kubelet **image GC** + eviction (`DiskPressure`).

## 7. cgroups + the OOM killer vs CUDA OOM
- Container memory limits are **cgroup** limits on **host RAM**. Exceed it → kernel
  OOM killer SIGKILLs the process → pod reason `OOMKilled`, exit **137**.
- **GPU VRAM has no cgroup.** A CUDA allocation failure raises in-process (exit
  **1**, `CrashLoopBackOff`) and is invisible to K8s. Detect via **DCGM**
  (`FB_USED`) + app logs. (See `scenarios/b-vram-oom`.)

## 8. DCGM field quick reference
`DCGM_FI_DEV_GPU_UTIL` (any kernel running, %) · `DCGM_FI_PROF_PIPE_TENSOR_ACTIVE`
(tensor-core cycles, fraction) · `DCGM_FI_DEV_FB_USED` / `FB_FREE` (VRAM MiB) ·
`DCGM_FI_PROF_DRAM_ACTIVE` (memory-bandwidth) · `DCGM_FI_DEV_POWER_USAGE` (W) ·
`DCGM_FI_DEV_GPU_TEMP` (°C) · `DCGM_FI_DEV_XID_ERRORS` (driver/HW faults).
**Compute-bound vs data-starved vs wrong-dtype** is read from UTIL + TENSOR_ACTIVE
+ DRAM_ACTIVE together, never UTIL alone.
