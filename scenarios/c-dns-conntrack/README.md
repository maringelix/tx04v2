# Scenario C — DNS + conntrack saturation at scale

> Run scripts inside the toolbox, for example
> `.\lab.ps1 run bash scenarios/c-dns-conntrack/break.sh`. Raw kubectl examples
> go through `.\lab.ps1 kubectl`; nothing is installed on the host.

Classic "the network is flaky" incident during distributed training. **Runbook:**
Symptom → Triage → Root cause → Fix → Prevention.

```bash
kubectl apply -f platform/30-serving/mock-llm.yaml   # conn-churn target
bash scenarios/c-dns-conntrack/break.sh
# ...triage...
bash scenarios/c-dns-conntrack/fix.sh
```

## Symptom
- Intermittent name-resolution failures and latency spikes across many pods once a
  large distributed job starts.
- Random connection timeouts / resets that don't map to any one service being down.

## Triage
```bash
# DNS
kubectl -n kube-system logs deploy/coredns --tail=50
kubectl -n scenario-c exec deploy/dns-storm -- cat /etc/resolv.conf   # ndots:5 + search list
# CoreDNS metrics (PromQL):
#   sum(rate(coredns_dns_requests_total[1m]))
#   sum(rate(coredns_dns_responses_total{rcode="SERVFAIL"}[1m]))
#   histogram_quantile(0.99, sum(rate(coredns_dns_request_duration_seconds_bucket[5m])) by (le))

# conntrack (kind node = Docker container)
docker exec tx04v2-worker sh -c 'cat /proc/sys/net/netfilter/nf_conntrack_count /proc/sys/net/netfilter/nf_conntrack_max'
docker exec tx04v2-worker dmesg 2>/dev/null | grep -i 'conntrack' | tail   # "table full, dropping packet"
```

## Root cause
Two compounding effects:
1. **DNS amplification.** `options ndots:5` + the multi-domain `search` list means
   every non-FQDN lookup becomes ~4–5 queries (each search suffix tried first,
   all NXDOMAIN, then the real name). Thousands of workers × this factor overwhelm
   CoreDNS → latency, then SERVFAIL.
2. **conntrack exhaustion.** Distributed workers (Ray/PyTorch rendezvous,
   AllReduce) open tens of thousands of short-lived connections; each is a
   conntrack entry lingering in TIME_WAIT. Cross `nf_conntrack_max` and the kernel
   silently **drops packets** → the app sees random timeouts.

## Fix
- **NodeLocal DNSCache** — a per-node cache so most queries never hit central
  CoreDNS, and cluster-zone misses forward over **TCP** (dodging UDP conntrack
  churn). (`platform/40-networking/nodelocaldns-install.sh`)
- **Kill ndots amplification** — set `dnsConfig` `ndots:1` for chatty workloads,
  or use fully-qualified names with a trailing dot (`api.github.com.`).
- **Scale CoreDNS** + cluster-proportional autoscaler; tune `cache`/`forward`.
- **Raise `nf_conntrack_max`** and shorten TCP timeouts
  (`platform/40-networking/conntrack-tuning.yaml`); **Cilium/eBPF** reduces
  per-flow tracking pressure.

## Prevention
- Alerts already shipped: `CoreDNSHighFailureRate`, `NodeConntrackNearLimit`
  (`platform/50-observability/prometheusrule-gpu.yaml`).
- Bake NodeLocal DNSCache + conntrack sysctls into the node image; set a low
  cluster-wide `ndots` default; capacity-plan CoreDNS with the fleet size.

## One-line interview version
> "Big training runs caused cluster-wide DNS SERVFAILs and random timeouts. Two
> root causes: ndots:5 was amplifying every lookup ~5x and swamping CoreDNS, and
> thousands of short-lived worker connections were filling the conntrack table
> until the kernel dropped packets. I fixed it with NodeLocal DNSCache + ndots:1,
> scaled CoreDNS, and raised conntrack limits — then added SERVFAIL and conntrack
> alerts so it's caught proactively."
