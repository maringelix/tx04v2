#!/usr/bin/env bash
# break.sh — run BOTH OOM cases side by side (CUDA VRAM vs host RAM).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ">> Applying the GPU VRAM OOM simulation and the host-RAM OOM contrast..."
kubectl apply -f "${DIR}/cuda-oom-sim.yaml"
kubectl apply -f "${DIR}/host-oom.yaml"

echo
echo ">> Wait ~30s (both will CrashLoopBackOff), then compare their status:"
cat <<'EOF'

# What the operator SEES for each:
kubectl -n ml-jobs get pods

# GPU VRAM OOM -> exit 1, reason NOT set to OOMKilled; truth is only in the logs:
kubectl -n ml-jobs logs cuda-oom-sim --previous | tail -5
kubectl -n ml-jobs get pod cuda-oom-sim \
  -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason} / exit={.status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}'

# Host RAM OOM -> reason=OOMKilled, exit 137, visible to K8s:
kubectl -n ml-jobs get pod host-oom \
  -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason} / exit={.status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}'
EOF
echo
echo ">> Read README.md for the runbook, then ./fix.sh"
