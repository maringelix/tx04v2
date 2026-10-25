# Validation harness

Validate tx04v2 with synthetic workloads on hosted CI runners or a disposable
lab machine. Do not run builds, dependency installations or fault-injection
suites on a host used for unrelated critical workloads. A new container or
worktree does not isolate the host's memory, disk or Docker daemon.

## Validation layers

The workflow in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) is the
executable definition of the checks. It covers repository checks, YAML and
Kubernetes manifests, launcher syntax, secret scanning, GPU rules/dashboard
queries and a hosted kind smoke test. Inspect the jobs for their exact scope and
read their output for the revision being reviewed.

| Layer | What it establishes | What it does not establish |
|---|---|---|
| Repository and secret checks | The inspected files meet the configured rules | A guarantee that arbitrary future content contains no sensitive information |
| Shell and PowerShell syntax | Launchers parse with the tested tools | Equivalent behavior on every host shell or OS |
| YAML and Kubernetes validation | The validated objects match their schemas | A running operator, available images or successful scheduling |
| Prometheus validation | Rules and dashboard expressions parse and configured rule tests pass | Live exporter wiring or a real GPU measurement |
| Hosted kind smoke | The exercised cluster/workload path works on that runner | Every optional module, hardware path, resource budget or break/fix scenario |

Do not infer a pass from this document. The evidence is the completed workflow
for the exact commit. Record failed, skipped or unexecuted checks explicitly.

## Local development

Shell, Git and read-only configuration inspection are appropriate without
starting the lab. On a disposable development machine, use the launcher so lab
CLIs stay inside the toolbox:

```bash
./lab.sh build
./lab.sh up
./lab.sh kubectl get nodes
./lab.sh kubectl get pods -A
```

`up` may build the toolbox implicitly. The toolbox mounts the Docker socket and
can control the daemon. Review image sources and commands before executing it.
Never point the lab's scripts at a shared or remote production kubeconfig.

## Runtime evidence

For a runtime change, record the source revision, host architecture, configured
Docker resources, cluster variant, commands and observed results. Check node
readiness and workload status after each module. When a scenario injects a
failure, show the failure and recovery rather than only a successful `apply`.

Use synthetic data and keep local kubeconfigs, credentials, logs and generated
outputs out of commits. Capture only the evidence needed to explain the result.

## Completion

Review every check for the proposed revision before merging. A failure is a
reason to diagnose the change, not to remove a check, suppress its exit code or
claim a validation that was not run. Teardown the disposable cluster after the
session with `TX04V2_ACK_DELETE_CLUSTER=tx04v2 ./lab.sh down`.
