#!/usr/bin/env bash
# fix.sh — apply Scenario A remediations and clean up the broken pods.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ">> Removing the broken demo pods..."
kubectl -n scenario-a delete pod huge-image disk-hog --ignore-not-found

echo ">> Deploying the image pre-puller (warm the cache on every node)..."
kubectl apply -f "${DIR}/prepuller-daemonset.yaml"
kubectl -n scenario-a rollout status ds/image-prepuller --timeout=120s || true

cat <<'EOF'

>> Durable fixes (what to SAY in the interview), layered:
   1) Pre-pull / cache the image on nodes  (prepuller-daemonset.yaml; or
      `kind load docker-image <img>` in this lab, `ctr images pull` on real nodes).
   2) Lazy pulling with SOCI / eStargz (Stargz snapshotter): the container starts
      before the image is fully downloaded, fetching layers on demand -> cuts
      cold-start of 10 GB+ images from minutes to seconds.
   3) Separate MODEL WEIGHTS from the image: ship a slim runtime image; pull
      weights via an initContainer from a PVC / object store, cached per node.
   4) Registry pull-through cache / mirror close to the cluster; smaller
      multi-stage images; pin digests.
   5) kubelet knobs: --serialize-image-pulls=false + --max-parallel-image-pulls,
      and image-gc-high/low thresholds so the node doesn't hit DiskPressure.

>> Cleanup: kubectl delete ns scenario-a
EOF
