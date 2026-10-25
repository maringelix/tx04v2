#!/usr/bin/env bash
# Install Prometheus, Grafana and GPU/DCGM telemetry in the disposable lab.
# Prometheus is one of the heaviest modules. Check available Docker memory
# before combining it with Cilium/Hubble and scale exercises.
set -euo pipefail

NS="monitoring"
RELEASE="kube-prom"
CHART_VERSION="${KUBE_PROMETHEUS_STACK_VERSION:-88.2.0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ">> Installing kube-prometheus-stack ${CHART_VERSION} into ns '${NS}'"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update prometheus-community >/dev/null

helm upgrade --install "${RELEASE}" prometheus-community/kube-prometheus-stack \
  --version "${CHART_VERSION}" \
  --namespace "${NS}" --create-namespace \
  -f "${SCRIPT_DIR}/kube-prometheus-stack-values.yaml" \
  --wait --timeout 10m

echo ">> Applying GPU/DCGM ServiceMonitor, dashboard and alerts..."
kubectl apply -f "${SCRIPT_DIR}/dcgm-servicemonitor.yaml"
kubectl apply -f "${SCRIPT_DIR}/grafana-dashboard-gpu.yaml"
kubectl apply -f "${SCRIPT_DIR}/prometheusrule-gpu.yaml"

cat <<MESSAGE

>> Done. Access the UIs (each in its own terminal):
   Grafana:     ./lab.sh grafana     -> http://localhost:3001 (admin/admin)
   Prometheus:  ./lab.sh prometheus  -> http://localhost:9090
   Windows: use the same commands with .\lab.ps1.
   The launchers publish these ports on host loopback only.

>> Confirm GPU metrics after installing platform/10-gpu:
   In Prometheus, query: DCGM_FI_DEV_GPU_UTIL
   If empty, check the exporter Service labels and ports against
   dcgm-servicemonitor.yaml using:
     ./lab.sh kubectl -n gpu-operator get svc --show-labels

>> Limits:
   Metrics are simulated by the fake GPU operator.
   Prometheus retains six hours in ephemeral storage.
   Alerts are evaluated locally; external notification delivery is not configured.
MESSAGE
