#!/usr/bin/env bash
# tx04v2 Docker-only launcher for Linux, macOS and Git Bash.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="${ROOT}/.state"
IMAGE="tx04v2-toolbox:local"
COMMAND="${1:-help}"
[ "$#" -gt 0 ] && shift

# Reject unsupported commands before inspecting Docker or building the toolbox.
case "${COMMAND}" in
  help|build|up|up-cilium|down|gpu|scheduling|serving|networking|observability|kwok|scale|kubectl|helm|run|grafana|prometheus) ;;
  *)
    echo "Unknown command '${COMMAND}'. Run ./lab.sh help." >&2
    exit 2 ;;
esac
if [ "${COMMAND}" = down ] && [ "${TX04V2_ACK_DELETE_CLUSTER:-}" != tx04v2 ]; then
  echo "Refusing to delete the tx04v2 cluster without TX04V2_ACK_DELETE_CLUSTER=tx04v2." >&2
  exit 2
fi

docker_ok() {
  command -v docker >/dev/null 2>&1 || { echo "Docker not found. No other host tool is required." >&2; exit 1; }
  docker info >/dev/null 2>&1 || { echo "Docker is installed but its daemon is not running." >&2; exit 1; }
}
build() {
  echo ">> Building the containerized toolchain (kind + kubectl + Helm)..."
  docker build -f "${ROOT}/Dockerfile.toolbox" -t "${IMAGE}" "${ROOT}"
}
ensure_image() { docker image inspect "${IMAGE}" >/dev/null 2>&1 || build; }
tool() {
  mkdir -p "${STATE}"
  local args=(run --rm -i --volume /var/run/docker.sock:/var/run/docker.sock
    --volume "${ROOT}:/workspace" --volume "${STATE}:/state")
  docker network inspect kind >/dev/null 2>&1 && args+=(--network kind)
  docker "${args[@]}" "${IMAGE}" "$@"
}
# Forward an in-cluster Service to the host. kubectl runs inside the ephemeral
# toolbox container and binds 0.0.0.0:<hostport>; --publish re-exposes that port
# on the host so a browser can reach it. (Plain `tool kubectl port-forward` binds
# only inside the toolbox and is unreachable from the host — hence this helper.)
# Usage: forward <namespace> <service> <hostport> <svcport>
forward() {
  local ns="$1" svc="$2" hostport="$3" svcport="$4"
  mkdir -p "${STATE}"
  local args=(run --rm -i --volume /var/run/docker.sock:/var/run/docker.sock
    --volume "${ROOT}:/workspace" --volume "${STATE}:/state"
    --publish "127.0.0.1:${hostport}:${hostport}")
  docker network inspect kind >/dev/null 2>&1 && args+=(--network kind)
  docker "${args[@]}" "${IMAGE}" \
    kubectl -n "${ns}" port-forward --address=0.0.0.0 "svc/${svc}" "${hostport}:${svcport}"
}
export_kubeconfig() { tool kind export kubeconfig --name tx04v2 --internal --kubeconfig /state/kubeconfig; }
up() {
  local variant="${1:-default}" config="clusters/kind/kind-cluster.yaml"
  [ "${variant}" = cilium ] && config="clusters/kind/kind-cluster-cilium.yaml"
  if ! docker ps -a --format '{{.Names}}' | grep -qx tx04v2-control-plane; then
    tool kind create cluster --name tx04v2 --config "/workspace/${config}" --wait 0s
  else
    echo ">> Cluster 'tx04v2' already exists."
  fi
  export_kubeconfig
  if [ "${variant}" = cilium ]; then
    tool bash platform/40-networking/install.sh
  else
    tool kubectl wait --for=condition=Ready nodes --all --timeout=180s
  fi
  tool kubectl get nodes -o wide
}
help() {
  cat <<'EOF'
tx04v2 — Docker-only Kubernetes AI/GPU lab

Host requirement: Docker Desktop only. Nothing else is installed on the host.

  ./lab.sh build                 Build the containerized toolchain
  ./lab.sh up                    Create the default kind cluster
  ./lab.sh up-cilium             Create the Cilium/eBPF cluster
  TX04V2_ACK_DELETE_CLUSTER=tx04v2 ./lab.sh down
                                 Delete the lab cluster in an explicit window
  ./lab.sh gpu                   Install the simulated GPU operator
  ./lab.sh scheduling            Install Volcano
  ./lab.sh serving               Deploy the mock LLM
  ./lab.sh networking            Install default-cluster network add-ons
  ./lab.sh observability         Install Prometheus and Grafana
  ./lab.sh kwok [count]          Create fake GPU nodes (default: 100)
  ./lab.sh scale                 Submit the 400-pod scale workload
  ./lab.sh kubectl <args...>     Run kubectl inside the toolbox
  ./lab.sh helm <args...>        Run Helm inside the toolbox
  ./lab.sh run <command...>      Run any toolbox command
  ./lab.sh grafana               Forward Grafana to localhost:3001 (admin/admin)
  ./lab.sh prometheus            Forward Prometheus to localhost:9090
EOF
}

case "${COMMAND}" in
  help) help ;;
  build) docker_ok; build ;;
  *)
    docker_ok
    ensure_image
    case "${COMMAND}" in
      up) up default ;;
      up-cilium) up cilium ;;
      down)
        tool kind delete cluster --name tx04v2
        rm -f "${STATE}/kubeconfig" ;;
      gpu) tool bash platform/10-gpu/install.sh ;;
      scheduling) tool bash platform/20-scheduling/install.sh ;;
      serving) tool kubectl apply -f platform/30-serving/mock-llm.yaml ;;
      networking)
        tool bash platform/40-networking/nodelocaldns-install.sh
        tool kubectl apply -f platform/40-networking/conntrack-tuning.yaml
        tool kubectl apply -f platform/40-networking/netpol.yaml ;;
      observability) tool bash platform/50-observability/install.sh ;;
      kwok)
        count="${1:-100}"; tool bash clusters/kwok/install.sh
        tool bash clusters/kwok/create-fake-nodes.sh "${count}" ;;
      scale) tool kubectl apply -f clusters/kwok/scale-workload.yaml ;;
      kubectl) tool kubectl "$@" ;;
      helm) tool helm "$@" ;;
      run) tool "$@" ;;
      grafana) forward monitoring kube-prom-grafana 3001 80 ;;
      prometheus) forward monitoring kube-prom-prometheus 9090 9090 ;;
      *) echo "Unknown command '${COMMAND}'. Run ./lab.sh help." >&2; exit 2 ;;
    esac ;;
esac
