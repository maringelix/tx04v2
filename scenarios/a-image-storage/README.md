# Scenario A — huge image pull / storage bottleneck

> Run scripts inside the toolbox, for example
> `.\lab.ps1 run bash scenarios/a-image-storage/break.sh`. Raw kubectl examples
> go through `.\lab.ps1 kubectl`; nothing is installed on the host.

**Runbook format:** Symptom → Triage → Root cause → Fix → Prevention.

```bash
bash scenarios/a-image-storage/break.sh   # induce
# ...triage (below)...
bash scenarios/a-image-storage/fix.sh     # remediate
```

## Symptom
- New GPU pods sit in `ContainerCreating` / `ImagePullBackOff` for minutes.
- Or nodes flip to `DiskPressure` and start `Evicting` pods; `df` shows the
  containerd image store filling up.

## Triage (structured debugging)
```bash
kubectl -n scenario-a get pods
kubectl -n scenario-a describe pod huge-image        # Events: Failed to pull / Back-off
kubectl -n scenario-a get events --sort-by=.lastTimestamp | tail -20
kubectl -n scenario-a get pod disk-hog \
  -o jsonpath='{.status.reason} {.status.message}{"\n"}'   # Evicted: ephemeral storage
# On the node (real cluster):
#   crictl images                     # what's cached & how big
#   crictl pull <image>               # time the pull
#   df -h /var/lib/containerd         # disk headroom
#   journalctl -u kubelet | grep -i -E 'image|evict|diskpressure'
kubectl describe node <node> | grep -A5 Conditions      # DiskPressure=True?
```

## Root cause
Deep-learning images (PyTorch + CUDA + cuDNN + model weights) are commonly
5–15 GB. On a cold node:
- the pull exceeds the kubelet image-pull timeout, or several big pulls run
  serially and starve each other → `ImagePullBackOff`;
- layers + extracted rootfs fill `/var/lib/containerd` → node crosses the
  eviction threshold → `DiskPressure` → evictions (cascading, since evicted pods
  reschedule elsewhere and repeat).

## Fix (durable, layered)
1. **Pre-pull / warm cache** on nodes (`prepuller-daemonset.yaml`; `kind load
   docker-image` here).
2. **Lazy pulling** with **SOCI / eStargz** (Stargz snapshotter): the container
   starts before the full image is downloaded; layers stream on demand.
3. **Separate weights from the image**: slim runtime image + initContainer that
   pulls weights from a PVC/object store, cached per node.
4. **Registry pull-through cache / mirror**; smaller multi-stage images; pin
   digests.
5. **kubelet tuning**: parallel image pulls (`--serialize-image-pulls=false`,
   `--max-parallel-image-pulls=N`) and `image-gc-high/low-threshold-percent` so
   the node reclaims space before DiskPressure.

## Prevention
- Alert early: `PodImagePullBackOff` and `NodeDiskPressure`
  (`platform/50-observability/prometheusrule-gpu.yaml`).
- Bake heavy images into the node image or a warm pool; provision extra ephemeral
  disk on GPU node pools; enforce image size budgets in CI.

## One-line interview version
> "10-GB CUDA images were timing out and filling node disk, causing
> ImagePullBackOff and DiskPressure evictions. Root cause was cold-node serial
> pulls with no caching. I fixed it durably with node pre-pull + SOCI lazy
> pulling and by moving model weights out of the image onto a per-node PVC cache,
> then added ImagePullBackOff/DiskPressure alerts so we catch it before users do."
