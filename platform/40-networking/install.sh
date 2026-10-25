#!/usr/bin/env bash
# =============================================================================
# install.sh — Install Cilium (eBPF) into the CILIUM kind cluster.
#
# PRECONDITION: the cluster was created with the cilium variant:
#   .\lab.ps1 up-cilium  (Windows) or ./lab.sh up-cilium
# (nodes will be NotReady until this finishes — that's expected: no CNI yet.)
#
# With kubeProxyReplacement and kube-proxy absent, Cilium needs the API server
# address directly (the in-cluster kubernetes Service isn't reachable until
# Cilium is up — a chicken-and-egg). We read the kind control-plane container's
# IP from Docker and pass it as k8sServiceHost.
# =============================================================================
set -euo pipefail

CILIUM_VERSION="${CILIUM_VERSION:-1.16.5}"
NS="kube-system"
RELEASE="cilium"
CP_CONTAINER="${CP_CONTAINER:-tx04v2-control-plane}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ">> Discovering kind control-plane IP from Docker ($CP_CONTAINER)..."
CP_IP="$(docker inspect "$CP_CONTAINER" -f '{{(index .NetworkSettings.Networks "kind").IPAddress}}' 2>/dev/null || true)"
if [ -z "$CP_IP" ]; then
  echo "!! Could not find $CP_CONTAINER on the 'kind' network. Is the cilium cluster up?"
  echo "   Run .\\lab.ps1 up-cilium (Windows) or ./lab.sh up-cilium"
  exit 1
fi
echo ">> control-plane IP = ${CP_IP}"

helm repo add cilium https://helm.cilium.io >/dev/null 2>&1 || true
helm repo update cilium >/dev/null

helm upgrade --install "${RELEASE}" cilium/cilium \
  --namespace "${NS}" \
  --version "${CILIUM_VERSION}" \
  -f "${SCRIPT_DIR}/cilium-values.yaml" \
  --set k8sServiceHost="${CP_IP}" \
  --set k8sServicePort=6443 \
  --wait --timeout 5m

echo ">> Waiting for nodes to become Ready (Cilium now provides the CNI)..."
kubectl wait --for=condition=Ready nodes --all --timeout=180s || true
kubectl get nodes -o wide

echo
echo ">> Verify Cilium + kube-proxy replacement:"
echo "   kubectl -n kube-system exec ds/cilium -- cilium status | grep -i kubeproxy"
echo "   kubectl -n kube-system exec ds/cilium -- cilium status --verbose | grep -iA2 'KubeProxyReplacement'"
echo ">> Hubble UI (if enabled):  kubectl -n kube-system port-forward svc/hubble-ui 12000:80"
