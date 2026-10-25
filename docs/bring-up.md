# Bring up a disposable lab

Use a machine dedicated to the exercise, with Docker Desktop running and enough
free memory and disk for the selected modules. Read [MAINTENANCE.md](MAINTENANCE.md)
and [HARNESS.md](HARNESS.md) first. No cloud account, application credentials or
physical GPU is required for the default path.

## 1. Inspect before starting

Review `Dockerfile.toolbox`, `lab.sh` or `lab.ps1`, and the selected kind
configuration. Check the configured host ports for collisions. The toolbox
mounts the Docker socket and creates sibling node containers; it is privileged
with respect to the local Docker daemon.

The configuration names the cluster `tx04v2`. Its kubeconfig and Helm state stay
in ignored `.state/`. Do not replace this kubeconfig with one for another cluster.

## 2. Start the basic cluster

```bash
./lab.sh up
./lab.sh kubectl get nodes -o wide
./lab.sh kubectl get pods -A
```

On PowerShell, replace `./lab.sh` with `.\lab.ps1`. The toolbox is built on
first use if it is absent. Expect one control plane and two workers; all three
should become `Ready` before continuing.

Choose `up-cilium` instead of `up` only when studying the Cilium variant. These
commands configure the same lab name differently. Delete an existing disposable
cluster before changing variants.

## 3. Add one module at a time

```bash
./lab.sh gpu
./lab.sh kubectl get nodes -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\\.com/gpu
./lab.sh scheduling
./lab.sh kubectl -n volcano-system get pods
```

The GPU resources and DCGM signals are simulated. KWOK is a separate optional
scale exercise; fake KWOK nodes do not execute workloads:

```bash
./lab.sh kwok 100
./lab.sh scale
./lab.sh kubectl get pods -n kwok-scale -o wide
```

Add observability when there is capacity:

```bash
./lab.sh observability
./lab.sh kubectl -n monitoring get pods
./lab.sh grafana
```

Keep the forward running and open `http://localhost:3001`; the lab credentials
are `admin` / `admin`. Run `./lab.sh prometheus` in another terminal to inspect
`http://localhost:9090` and query `DCGM_FI_DEV_GPU_UTIL`. These services are local
lab interfaces, not internet-facing endpoints.

Read each module's README before installing serving, networking or custom metrics.
Applying an HPA alone is not sufficient: its metric source and adapter must also
be available. Cilium/Hubble, monitoring and a scale scenario can compete for the
same resources; avoid starting all of them at once on a small machine.

## 4. Practice a scenario

Choose one of the [break/fix scenarios](../README.md#breakfix-scenarios), read its
manifests, then run its commands through the launcher. Observe the intended
failure, apply the documented recovery and check the result. Do not use an
unrelated workload as the target of a lab exercise.

## 5. Delete the disposable cluster

```bash
TX04V2_ACK_DELETE_CLUSTER=tx04v2 ./lab.sh down
```

```powershell
$env:TX04V2_ACK_DELETE_CLUSTER = 'tx04v2'
.\lab.ps1 down
```

This deletes the exact lab cluster. It is not a command for reclaiming space from
unrelated workloads. Avoid global Docker prune commands. If the toolbox image
is no longer needed, remove that exact image with
`docker image rm tx04v2-toolbox:local`.
