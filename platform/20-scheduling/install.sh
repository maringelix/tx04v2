#!/usr/bin/env bash
# =============================================================================
# install.sh — Install the Volcano batch/gang scheduler into ns volcano-system.
#
# WHY: The default kube-scheduler places pods one-at-a-time and has no concept
# of "all-or-nothing" (gang) scheduling. Distributed training (synchronous SGD
# / AllReduce) needs ALL N workers running at once or none of them make
# progress. Volcano adds a PodGroup abstraction + a gang plugin so a job only
# starts once minMember pods can be co-placed, plus queues, fair-share,
# binpack, priority and preemption — the scheduling features a GPU AI platform
# lives or dies by.
#
# This installs the Volcano control plane: the CRDs (Job, Queue, PodGroup),
# the volcano-scheduler (the actual scheduler binary), the volcano-controllers
# (Job lifecycle -> PodGroup/Pods), and the admission webhook (defaulting +
# validation, e.g. injecting schedulerName=volcano).
#
# Idempotent: re-running upgrades the release in place (helm upgrade --install).
# Pinned to a known-good version; override with VOLCANO_VERSION.
# =============================================================================
set -euo pipefail

VOLCANO_VERSION="${VOLCANO_VERSION:-1.15.0}"          # chart + image version (no leading v for the chart)
VOLCANO_NS="${VOLCANO_NS:-volcano-system}"
VOLCANO_RELEASE="${VOLCANO_RELEASE:-volcano}"
HELM_REPO_NAME="volcano-sh"
HELM_REPO_URL="https://volcano-sh.github.io/helm-charts"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ">> Installing Volcano ${VOLCANO_VERSION} (release '${VOLCANO_RELEASE}') into ns '${VOLCANO_NS}'"

# ---------------------------------------------------------------------------
# 1) Install / upgrade the Volcano control plane via Helm.
#    --create-namespace makes this self-contained per the lab convention.
#    We DO NOT replace the default kube-scheduler — Volcano runs ALONGSIDE it
#    as a second scheduler. Pods opt in via spec.schedulerName: volcano (the
#    Volcano Job controller sets this automatically on the pods it creates).
# ---------------------------------------------------------------------------
helm repo add "${HELM_REPO_NAME}" "${HELM_REPO_URL}" >/dev/null 2>&1 || true
helm repo update "${HELM_REPO_NAME}" >/dev/null

helm upgrade --install "${VOLCANO_RELEASE}" "${HELM_REPO_NAME}/volcano" \
  --namespace "${VOLCANO_NS}" \
  --create-namespace \
  --version "${VOLCANO_VERSION}" \
  --wait \
  --timeout 5m

# ---------------------------------------------------------------------------
# 2) Wait for the scheduler + controller + webhook to be Ready. If the webhook
#    is not up yet, applying a Volcano Job can fail admission, so we block here.
# ---------------------------------------------------------------------------
echo ">> Waiting for Volcano components to become Ready..."
kubectl -n "${VOLCANO_NS}" rollout status deploy/volcano-scheduler   --timeout=180s
kubectl -n "${VOLCANO_NS}" rollout status deploy/volcano-controllers --timeout=180s
kubectl -n "${VOLCANO_NS}" rollout status deploy/volcano-admission    --timeout=180s

# ---------------------------------------------------------------------------
# 3) Apply the lab's ML queue. The Volcano default queue ("default") is created
#    by the installer; we add a dedicated, weighted queue for ML jobs so we can
#    demonstrate fair-share and capacity caps.
# ---------------------------------------------------------------------------
echo ">> Applying ML queue..."
kubectl apply -f "${SCRIPT_DIR}/queue.yaml"

# ---------------------------------------------------------------------------
# 4) Show the scheduler configuration so the operator can SEE which plugins are
#    active (gang, conformance, drf, predicates, proportion, nodeorder,
#    binpack). The gang plugin is what enforces all-or-nothing.
# ---------------------------------------------------------------------------
echo ">> Volcano scheduler plugin config (volcano-scheduler-configmap):"
kubectl -n "${VOLCANO_NS}" get configmap volcano-scheduler-configmap -o yaml \
  | sed 's/^/   /' || true

echo
echo ">> Volcano installed. Verify with:"
echo "   kubectl -n ${VOLCANO_NS} get pods"
echo "   kubectl get queues.scheduling.volcano.sh"
echo "   kubectl explain job.spec.minAvailable --api-version=batch.volcano.sh/v1alpha1"
echo
echo ">> Next: run the gang demo ->  kubectl apply -f ${SCRIPT_DIR}/gang-training-job.yaml"
echo "   Watch all-or-nothing ->     kubectl get podgroups,pods -n ml-jobs -w"
