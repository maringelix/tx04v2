#!/usr/bin/env bash
# =============================================================================
# nodelocaldns-install.sh — deploy NodeLocal DNSCache the canonical way.
#
# NodeLocal DNSCache runs a CoreDNS cache as a DaemonSet on EVERY node, listening
# on a link-local address (169.254.20.10). Pods' DNS traffic is intercepted
# locally, so:
#   * cache hits never leave the node -> huge drop in CoreDNS QPS + tail latency,
#   * cluster-zone misses are forwarded to CoreDNS over TCP (avoids UDP conntrack
#     churn -> fewer "conntrack table full" drops during distributed jobs),
#   * a single crashed CoreDNS pod no longer spikes every pod's DNS latency.
#
# We use the OFFICIAL kubernetes/kubernetes manifest and substitute the three
# "pillar" tokens for THIS cluster (the other two are filled by the node-cache
# binary at runtime from the kube-dns-upstream Service + /etc/resolv.conf). This
# is exactly how it's done in production, so the method itself is the lesson.
#
#   __PILLAR__LOCAL__DNS__  = 169.254.20.10   (link-local listen IP)
#   __PILLAR__DNS__DOMAIN__ = cluster.local   (cluster domain)
#   __PILLAR__DNS__SERVER__ = 10.96.0.10      (kube-dns Service ClusterIP)
#
# NOTE: run this on the DEFAULT (kube-proxy) cluster. On the Cilium
# kube-proxy-replacement cluster, use Cilium's local-redirect policy instead.
# =============================================================================
set -euo pipefail

LOCALDNS="${LOCALDNS:-169.254.20.10}"
DNSDOMAIN="${DNSDOMAIN:-cluster.local}"
# kube-dns Service ClusterIP (serviceSubnet 10.96.0.0/16 -> .10 by convention).
KUBEDNS="${KUBEDNS:-$(kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo 10.96.0.10)}"
URL="${URL:-https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/dns/nodelocaldns/nodelocaldns.yaml}"

echo ">> Installing NodeLocal DNSCache (local=${LOCALDNS}, domain=${DNSDOMAIN}, kube-dns=${KUBEDNS})"
curl -fsSL "$URL" \
  | sed -e "s/__PILLAR__LOCAL__DNS__/${LOCALDNS}/g" \
        -e "s/__PILLAR__DNS__DOMAIN__/${DNSDOMAIN}/g" \
        -e "s/__PILLAR__DNS__SERVER__/${KUBEDNS}/g" \
  | kubectl apply -f -

echo ">> Waiting for node-local-dns DaemonSet..."
kubectl -n kube-system rollout status ds/node-local-dns --timeout=120s || true

echo
echo ">> Verify:"
echo "   kubectl -n kube-system get pods -l k8s-app=node-local-dns -o wide"
echo "   kubectl -n kube-system logs ds/node-local-dns | head"
echo ">> NOTE: for pods to USE it, the kubelet must set --cluster-dns=${LOCALDNS}"
echo "   (managed clusters do this automatically; on kind, pods still work via"
echo "    the cache bound on the kube-dns ClusterIP too)."
