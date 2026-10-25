#!/usr/bin/env bash
# =============================================================================
# create-fake-nodes.sh N — Register N fake GPU nodes via KWOK.
#
# Usage:   bash clusters/kwok/create-fake-nodes.sh 100
# Default: 100 nodes, i.e. 100 * 8 = 800 simulated A100 GPUs.
#
# Each node is a copy of fake-gpu-node.yaml with a unique name. Because the
# nodes carry status.allocatable nvidia.com/gpu=8, the REAL scheduler will place
# GPU pods across them exactly as it would on a real 800-GPU fleet — but nothing
# actually runs, so it costs a few MB of etcd, not a datacenter.
# =============================================================================
set -euo pipefail

COUNT="${1:-100}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/fake-gpu-node.yaml"

echo ">> Creating ${COUNT} fake GPU nodes (8 GPUs each = $((COUNT * 8)) simulated GPUs)..."

# Build one big manifest and apply once (far faster than N kubectl calls).
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
for i in $(seq 1 "${COUNT}"); do
  name="$(printf 'kwok-gpu-%04d' "$i")"
  sed "s/__NODE_NAME__/${name}/g" "${TEMPLATE}" >>"$tmp"
  echo '---' >>"$tmp"
done
kubectl apply -f "$tmp"

echo
echo ">> Done. Fleet view:"
echo "   kubectl get nodes -l type=kwok --no-headers | wc -l"
echo "   kubectl describe nodes -l type=kwok | grep -A3 Allocatable | head"
echo ">> Total schedulable GPUs across the fake fleet:"
echo "   kubectl get nodes -l type=kwok -o jsonpath='{range .items[*]}{.status.allocatable.nvidia\.com/gpu}{\"\\n\"}{end}' | paste -sd+ | bc"
