#!/usr/bin/env bash
# break.sh — induce DNS + conntrack saturation.
# NOTE: conn-churn targets mock-llm; deploy platform/30-serving first (or edit
# the target). dns-storm works standalone.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ">> Starting the DNS storm and connection churn..."
kubectl apply -f "${DIR}/dns-storm.yaml"
kubectl apply -f "${DIR}/conn-churn.yaml"

cat <<'EOF'

>> TRIAGE — DNS side:
   kubectl -n kube-system logs deploy/coredns --tail=50
   # CoreDNS request rate & errors (port-forward Prometheus, then query):
   #   sum(rate(coredns_dns_requests_total[1m]))
   #   sum(rate(coredns_dns_responses_total{rcode="SERVFAIL"}[1m]))
   #   histogram_quantile(0.99, sum(rate(coredns_dns_request_duration_seconds_bucket[5m])) by (le))
   # See the ndots amplification from inside a pod:
   kubectl -n scenario-c exec deploy/dns-storm -- cat /etc/resolv.conf

>> TRIAGE — conntrack side (kind nodes are Docker containers):
   docker exec tx04v2-worker sh -c 'cat /proc/sys/net/netfilter/nf_conntrack_count; cat /proc/sys/net/netfilter/nf_conntrack_max'
   docker exec tx04v2-worker sh -c 'conntrack -S 2>/dev/null | head || true'
   docker exec tx04v2-worker dmesg 2>/dev/null | grep -i conntrack | tail

>> Then read README.md and run ./fix.sh
EOF
