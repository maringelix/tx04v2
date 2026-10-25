#!/usr/bin/env bash
# break.sh — induce Scenario A failures (ImagePullBackOff + ephemeral eviction).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ">> Applying broken workloads..."
kubectl apply -f "${DIR}/huge-image.yaml"
kubectl apply -f "${DIR}/disk-pressure.yaml"

echo
echo ">> Give it ~30s, then TRIAGE:"
echo "   kubectl -n scenario-a get pods"
echo "   kubectl -n scenario-a describe pod huge-image | sed -n '/Events/,\$p'"
echo "   kubectl -n scenario-a get events --sort-by=.lastTimestamp | tail -20"
echo "   kubectl -n scenario-a get pod disk-hog -o jsonpath='{.status.reason} {.status.message}{\"\\n\"}'"
echo
echo ">> Then read the runbook (README.md) and run ./fix.sh"
