# tx04v2 — Kubernetes AI/GPU platform lab

tx04v2 is a laptop-sized lab for learning how an AI compute platform works. It
combines a real Kubernetes control plane and worker nodes with simulated GPUs
and an optional KWOK fleet for scheduler experiments.

**Docker Desktop is the only host prerequisite.** The pinned
[toolbox image](Dockerfile.toolbox) contains kind, kubectl, Helm and Bash.
The launchers run those tools in disposable containers, with state under the
ignored `.state/` directory. They do not change the host's kubeconfig or install
packages on the host.

Use a disposable lab machine. The exercises intentionally create resource
pressure, failing pods and networking faults. Containers share the Docker
daemon's memory and disk budget, so this lab must not run beside workloads that
need uninterrupted service. Read the [validation harness](docs/HARNESS.md) and
[maintenance guide](docs/MAINTENANCE.md) before operating it.

## What is included

| Area | Implementation | What it demonstrates |
|---|---|---|
| Cluster | kind, with an optional Cilium variant | Multi-node lifecycle and CNI choices |
| GPU | run:ai fake GPU operator | Device plugins, `nvidia.com/gpu` and DCGM-style telemetry |
| Scale | KWOK fake GPU nodes | Scheduler behavior across hundreds of nodes and GPUs |
| Batch | Volcano | Gang scheduling, queues, fairness and bin packing |
| Serving | Mock LLM, Prometheus Adapter and HPA manifests | Inference concurrency and autoscaling concepts |
| Networking | Cilium, NodeLocal DNSCache and conntrack examples | eBPF, DNS and network policy |
| Observability | Prometheus, Grafana and GPU dashboards/alerts | GPU utilization, memory and health signals |
| Incidents | Three break/fix runbooks | Image/disk pressure, VRAM OOM and DNS/conntrack exhaustion |

The default lab does not execute CUDA workloads. The kind control plane and
workers are real Kubernetes nodes, GPUs are simulated, and KWOK nodes do not run
containers. Optional real-hardware examples have separate prerequisites. See
[the architecture](docs/architecture.md) for these boundaries.

## Quick start

From a disposable machine with Docker Desktop running:

```bash
git clone https://github.com/maringelix/tx04v2.git
cd tx04v2
./lab.sh up
./lab.sh gpu
./lab.sh kubectl get nodes
```

On Windows, use PowerShell:

```powershell
git clone https://github.com/maringelix/tx04v2.git
Set-Location tx04v2
.\lab.ps1 up
.\lab.ps1 gpu
.\lab.ps1 kubectl get nodes
```

The first `up` builds the toolbox if it does not exist. See the
[bring-up guide](docs/bring-up.md) for resource checks, module order and teardown.

## Commands

Run `./lab.sh help` or `.\lab.ps1 help` for the launcher interface.

| Command | Purpose |
|---|---|
| `build` | Build the local toolbox |
| `up` | Create the default kindnet cluster |
| `up-cilium` | Create the no-kube-proxy cluster and install Cilium |
| `gpu` | Install the simulated GPU operator |
| `scheduling` | Install Volcano and its queue |
| `serving` | Deploy the mock LLM |
| `networking` | Install DNS, conntrack and network-policy examples |
| `observability` | Install Prometheus, Grafana, GPU dashboards and alerts |
| `kwok [count]` | Install KWOK and create fake GPU nodes; default 100 |
| `scale` | Submit the scheduler scale workload |
| `grafana` | Forward Grafana to `localhost:3001` |
| `prometheus` | Forward Prometheus to `localhost:9090` |
| `kubectl ...` | Run kubectl inside the toolbox |
| `helm ...` | Run Helm inside the toolbox |
| `run ...` | Run a command inside the toolbox |
| `down` | Delete only the lab cluster; requires explicit acknowledgement |

Examples in deeper documents may show raw kubectl or Helm commands. Run them
through `./lab.sh kubectl`, `./lab.sh helm` or the corresponding PowerShell
command. For a pipeline, run a shell inside the toolbox:

```bash
./lab.sh run bash -lc 'kubectl get pods -A | head'
```

## Isolation and teardown

The cluster is named `tx04v2` and the toolbox image is `tx04v2-toolbox:local`.
The kubeconfig and Helm cache are isolated under `.state/`. The toolbox mounts
the Docker socket so kind can create sibling node containers; this grants it
control over the local Docker daemon. Review the launchers and Dockerfile before
running them.

Teardown is deliberately explicit:

```bash
TX04V2_ACK_DELETE_CLUSTER=tx04v2 ./lab.sh down
```

```powershell
$env:TX04V2_ACK_DELETE_CLUSTER = 'tx04v2'
.\lab.ps1 down
```

Do not use global Docker cleanup commands to remove the lab. The optional
toolbox cleanup is `docker image rm tx04v2-toolbox:local` after teardown.

## Break/fix scenarios

1. [Image pulls and disk pressure](scenarios/a-image-storage/README.md)
2. [CUDA/VRAM OOM versus host OOM](scenarios/b-vram-oom/README.md)
3. [DNS amplification and conntrack exhaustion](scenarios/c-dns-conntrack/README.md)

Run failure injection only in the disposable lab, through the launcher. Start
with one scenario and follow its recovery steps before moving to another.

## Repository map

```text
Dockerfile.toolbox         containerized CLI toolchain
lab.ps1 / lab.sh           Docker-only entry points
clusters/                  kind substrate and KWOK fleet
platform/10-gpu/           simulated GPU device plugin and metrics
platform/20-scheduling/    Volcano jobs, queues and deadlock demo
platform/30-serving/       mock inference, custom metrics and HPA
platform/40-networking/    Cilium, DNS, conntrack and network policy
platform/50-observability/ Prometheus, Grafana and GPU telemetry
scenarios/                 break/fix exercises
docs/                      architecture, operation and technical reference
```

Use the [cheatsheet](docs/cheatsheet.md), [mechanism notes](docs/under-the-hood.md)
and [interview guide](docs/interview-guide.md) to connect observations with the
underlying Kubernetes behavior. Validation scope and limitations are documented
in [HARNESS.md](docs/HARNESS.md); a passing static check does not prove every
optional module has run successfully on a given machine.

## License

[MIT](LICENSE)
