#!/usr/bin/env bash
# fix.sh — apply the DNS/conntrack remediations, then stop the storm.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo ">> 1) NodeLocal DNSCache: cache DNS per-node, forward misses over TCP."
bash "${REPO_ROOT}/platform/40-networking/nodelocaldns-install.sh" || true

echo ">> 2) conntrack tuning: raise nf_conntrack_max + shorten timeouts."
kubectl apply -f "${REPO_ROOT}/platform/40-networking/conntrack-tuning.yaml"

echo ">> 3) Kill ndots amplification for the noisy workload (ndots:1 + FQDNs)."
kubectl -n scenario-c patch deploy dns-storm --type merge -p '{
  "spec": {"template": {"spec": {"dnsConfig": {"options": [{"name": "ndots", "value": "1"}]}}}}
}' || true

echo ">> 4) (Optional) give CoreDNS more headroom:"
echo "     kubectl -n kube-system scale deploy/coredns --replicas=3"

echo
echo ">> Stopping the storm..."
kubectl delete ns scenario-c --ignore-not-found

cat <<'EOF'

>> Durable fixes summary (interview):
   * NodeLocal DNSCache  -> most queries never reach central CoreDNS; TCP forward
     avoids UDP conntrack churn.
   * ndots:1 / trailing-dot FQDNs -> kills search-domain amplification (5x -> 1x).
   * Scale CoreDNS + cluster-proportional-autoscaler; tune cache/forward.
   * Raise nf_conntrack_max + shorter timeouts; Cilium/eBPF reduces per-flow
     tracking pressure.
   * Alert on CoreDNS SERVFAIL rate + conntrack > 80% (already in observability).
EOF
