#!/usr/bin/env bash
# =============================================================================
# install.sh — Install KWOK (Kubernetes WithOut Kubelet) in "in-cluster" mode.
#
# WHY KWOK: kind gives us a handful of REAL nodes (Docker containers running a
# real kubelet + containerd). That is honest but heavy — you will not fit
# "hundreds of nodes" on an 8 GB laptop. KWOK deploys a single controller that
# IMPERSONATES the kubelet for nodes annotated  kwok.x-k8s.io/node=fake : it
# writes their heartbeats/status and drives the pod lifecycle (Pending ->
# Running -> ...) WITHOUT ever starting a container. The api-server, etcd, and
# the REAL kube-scheduler treat these fake nodes as first-class, so you can:
#   * schedule 100s of GPU pods and watch the scheduler's binpack/spread/gang
#     behavior at scale,
#   * exercise autoscaler / descheduler / quota / priority logic,
#   * reproduce "hundreds of nodes / tens of clusters" scale scenarios
# all on a laptop. What is REAL: control plane + scheduling decisions. What is
# FAKE: the kubelet + container runtime (no workload actually runs).
#
# Two manifests are applied:
#   kwok.yaml       -> the kwok-controller Deployment (into kube-system).
#   stage-fast.yaml -> "Stages" (CRs) that tell kwok to transition fake pods to
#                      Running instantly and node heartbeats quickly.
# =============================================================================
set -euo pipefail

KWOK_REPO="kubernetes-sigs/kwok"
# Resolve the latest release, but fall back to a known-good pin if the API call
# is rate-limited / offline. Override with KWOK_VERSION=v0.x.y.
KWOK_VERSION="${KWOK_VERSION:-$(curl -fsSL "https://api.github.com/repos/${KWOK_REPO}/releases/latest" 2>/dev/null | grep -oE '"tag_name": *"[^"]+"' | head -1 | cut -d'"' -f4)}"
KWOK_VERSION="${KWOK_VERSION:-v0.6.1}"

echo ">> Installing KWOK ${KWOK_VERSION} (in-cluster mode) into kube-system"

kubectl apply -f "https://github.com/${KWOK_REPO}/releases/download/${KWOK_VERSION}/kwok.yaml"
kubectl apply -f "https://github.com/${KWOK_REPO}/releases/download/${KWOK_VERSION}/stage-fast.yaml"

echo ">> Waiting for the kwok-controller to be Ready..."
kubectl -n kube-system rollout status deploy/kwok-controller --timeout=120s

echo
echo ">> KWOK ready. Create fake GPU nodes with:"
echo "     bash clusters/kwok/create-fake-nodes.sh 100"
echo ">> Then schedule at scale:"
echo "     kubectl apply -f clusters/kwok/scale-workload.yaml"
echo "     kubectl get pods -n kwok-scale -o wide | head"
echo ">> Tear down fake nodes:  kubectl delete nodes -l type=kwok"
