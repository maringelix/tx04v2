# Operating and maintaining tx04v2

This guide describes a disposable Kubernetes AI/GPU lab. All workloads and data
are synthetic. Read [HARNESS.md](HARNESS.md) before running validation or changing
the toolchain, and [bring-up.md](bring-up.md) for a first session.

## Runtime contract

| Component | Boundary |
|---|---|
| Host | Docker Desktop and the shell used by the launcher |
| Toolbox | kind, kubectl, Helm, Bash and supporting CLI tools |
| Cluster | One kind control plane and two worker containers |
| State | Kubeconfig and Helm cache in ignored `.state/` |
| GPU | Simulated device-plugin resources and telemetry; no CUDA by default |
| KWOK | Simulated nodes without kubelets or workload execution |
| Monitoring | In-cluster lab metrics, GPU dashboard and alert rules |

The toolbox needs the Docker socket to manage kind node containers. This is
privileged access to the whole daemon. Exact cluster names and namespaces prevent
accidental targeting, but they do not reserve physical RAM or disk capacity.
Use a machine that can be reset and has no unrelated critical workloads.

## Toolchain and versions

| Component | Version | Configuration |
|---|---|---|
| Toolbox base | `alpine:3.22` | `Dockerfile.toolbox` |
| kind | `v0.30.0` | `Dockerfile.toolbox` |
| kubectl | `v1.31.2` | `Dockerfile.toolbox` |
| Helm | `v3.16.4` | `Dockerfile.toolbox` |
| Kubernetes node | `kindest/node:v1.31.2` | `clusters/kind/` |
| Fake GPU operator | `0.1.0` | `platform/10-gpu/install.sh` |
| Volcano | `1.15.0` | `platform/20-scheduling/install.sh` |
| Cilium | `1.16.5` | `platform/40-networking/install.sh` |
| kube-prometheus-stack | `88.2.0` | `platform/50-observability/install.sh` |

These are the repository's configured versions, not a statement of current
vendor support or security status. Evaluate compatibility and release notes
before a version update. Update the manifests, toolbox, validators and docs as
one change; validate against the actual Kubernetes version used by kind.

Some optional downloads still follow upstream moving references: the KWOK
installer resolves a latest release and the NodeLocal DNS helper downloads from
the Kubernetes `master` branch. These paths are not fully reproducible or covered
by the basic hosted smoke test. Review the fetched content before using those
optional modules; replacing moving references with verified versions is separate
maintenance work.

## Resource planning

The slim observability profile requests modest resources and retains six hours
of Prometheus data. It does not make the whole stack lightweight: Prometheus,
Cilium/Hubble and scale scenarios can compete for the same Docker VM resources.
Start with the basic cluster, add one module at a time, and inspect node capacity
and pod events before adding a load generator.

The roughly 8 GiB budget described in example configurations is a planning
starting point, not a guarantee for every combination. Measure the host and the
Docker VM separately. A pod that is not marked `OOMKilled` does not prove the
host avoided memory pressure. The disk and OOM scenarios intentionally consume
resources; read their manifests before starting them.

## Cluster lifecycle

The default cluster is `tx04v2`, with nodes `tx04v2-control-plane`,
`tx04v2-worker` and `tx04v2-worker2`. `up` creates the kindnet variant;
`up-cilium` creates a separate configuration of the same lab name. Choose one
variant for a session. Delete the existing disposable cluster before switching
variants; do not apply a different CNI over an existing cluster by accident.

Run cluster administration through the launcher so it uses the lab kubeconfig:

```bash
./lab.sh kubectl get nodes -o wide
./lab.sh kubectl get pods -A
./lab.sh helm list -A
```

`down` destroys the exact lab cluster and its isolated kubeconfig. It requires
`TX04V2_ACK_DELETE_CLUSTER=tx04v2`. Do not use `docker system prune`, restart the
daemon as a routine diagnostic, or delete containers by a partial name.

## Monitoring

The observability installer applies the GPU/DCGM ServiceMonitor, Grafana
dashboard and PrometheusRule after installing the pinned chart. The objects
carry `release: kube-prom` so the chart's selectors can discover them.

```bash
./lab.sh observability
./lab.sh kubectl -n monitoring get pods
./lab.sh kubectl get servicemonitors,prometheusrules -A
./lab.sh grafana
```

Run `./lab.sh prometheus` in another terminal and query
`DCGM_FI_DEV_GPU_UTIL`. A missing series can mean the GPU module is absent or
the ServiceMonitor label, namespace, port or endpoint does not match its service.
Inspect those objects before changing the dashboard.

Grafana's example credentials are `admin` / `admin`, for the local lab only.
Do not publish these services on the internet. Prometheus uses ephemeral storage
with six-hour retention; recreating the pod can discard metrics. Alertmanager
is disabled in the slim profile, so alerts are inspected in the Prometheus UI;
this configuration does not send notifications.

The installer performs a Helm upgrade and reapplies lab objects. Review values
before rerunning it. For a dashboard or rule-only edit in a disposable session,
apply the exact changed manifest through the launcher.

## Maintenance workflow

1. Inspect the current branch and preserve unrelated local edits.
2. Make the change with documentation and matching validation.
3. Run the required checks on a hosted runner or a disposable machine.
4. Record the exact revision, commands, results and known limits.
5. Review the diff and all checks before merging.

Use synthetic identifiers and reserved example domains. Keep secrets, local
state, logs, private addresses and machine-specific configuration out of Git.
The history of a public repository is also public; removing a file in a later
commit does not remove earlier versions.

## Troubleshooting

| Symptom | Inspect |
|---|---|
| Cluster creation fails | Docker capacity, existing exact cluster name and configured port collisions |
| Nodes are `NotReady` | Node conditions, CNI and system pods |
| GPU pod stays pending | Resource requests, node labels, plugin pods and allocatable GPU count |
| Volcano job stays pending | Queue, PodGroup minimum membership and available resources |
| Mock service does not scale | HPA conditions, metric series and custom-metrics adapter configuration |
| Dashboard is empty | Monitor selectors, endpoint port and direct PromQL query |
| Unexpected pod exit | Termination reason, previous logs, events and host memory pressure |
| DNS failures | CoreDNS, search paths, NodeLocal DNS and conntrack counters |

The [three scenario runbooks](../README.md#breakfix-scenarios) contain targeted
recovery procedures. A successful static validation or one smoke test is not
evidence that every scenario, optional hardware path or CNI combination works.
