#!/usr/bin/env bash
# =============================================================================
# install.sh — Install run-ai/fake-gpu-operator so the cluster advertises
# nvidia.com/gpu and emits fake DCGM metrics WITHOUT any real GPU/driver.
#
# What gets deployed into ns gpu-operator:
#   * status-updater      -> patches node status.capacity/allocatable with
#                            nvidia.com/gpu on labeled nodes.
#   * device-plugin       -> speaks the kubelet device-plugin gRPC API so the
#                            kubelet believes the node has GPUs to allocate.
#   * (fake) dcgm-exporter -> exposes DCGM_FI_DEV_* metrics on :9400 for
#                            Prometheus (see platform/50-observability).
#   * admission webhook   -> injects a fake nvidia-smi + NVIDIA_VISIBLE_DEVICES
#                            into pods that request nvidia.com/gpu.
#
# Only nodes labeled  run.ai/simulated-gpu-node-pool=<pool>  participate; our
# kind GPU worker is pre-labeled  =default  to match fake-gpu-operator-values.yaml.
# Idempotent (helm upgrade --install).
# =============================================================================
set -euo pipefail

FGPU_VERSION="${FGPU_VERSION:-0.1.0}"
FGPU_CHART="oci://ghcr.io/run-ai/fake-gpu-operator/fake-gpu-operator"
NS="${GPU_NS:-gpu-operator}"
RELEASE="${GPU_RELEASE:-gpu-operator}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ">> Installing fake-gpu-operator ${FGPU_VERSION} (release '${RELEASE}') into ns '${NS}'"

# Ensure the GPU node actually carries the pool label (in case someone recreated
# the node or is running on a cluster that wasn't built from our kind config).
if ! kubectl get nodes -l run.ai/simulated-gpu-node-pool=default --no-headers 2>/dev/null | grep -q .; then
  echo ">> No node has label run.ai/simulated-gpu-node-pool=default; labeling the gpu-pool worker..."
  node="$(kubectl get nodes -l node.tx04v2.io/pool=gpu -o name 2>/dev/null | head -1)"
  [ -z "$node" ] && node="$(kubectl get nodes -o name | grep worker | head -1)"
  [ -n "$node" ] && kubectl label "$node" run.ai/simulated-gpu-node-pool=default --overwrite
fi

helm upgrade --install "${RELEASE}" "${FGPU_CHART}" \
  --namespace "${NS}" --create-namespace \
  --version "${FGPU_VERSION}" \
  -f "${SCRIPT_DIR}/fake-gpu-operator-values.yaml" \
  --wait --timeout 5m

echo ">> Waiting for GPUs to be advertised on the node..."
for i in $(seq 1 30); do
  cap="$(kubectl get nodes -l run.ai/simulated-gpu-node-pool=default \
        -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}' 2>/dev/null || true)"
  [ -n "$cap" ] && { echo ">> Node now advertises nvidia.com/gpu=${cap}"; break; }
  sleep 4
done

echo
echo ">> Verify:"
echo "   kubectl get nodes -o custom-columns=NODE:.metadata.name,GPU:.status.allocatable.nvidia\\.com/gpu"
echo "   kubectl -n ${NS} get pods"
echo "   kubectl apply -f ${SCRIPT_DIR}/sample-gpu-pod.yaml"
echo "   kubectl exec -it gpu-smoke -- nvidia-smi     # fake nvidia-smi injected by the webhook"
