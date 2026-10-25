# platform/40-networking — CNI (Cilium/eBPF), DNS, conntrack, NetworkPolicy

> **Docker-only:** use `.\lab.ps1 up-cilium` / `./lab.sh up-cilium`. Raw
> kubectl commands go through the launcher; no host CLI installation is needed.

The networking depth the JD asks about: how packets, Services, and DNS actually
work, and how they break under the load of distributed training. This module also
underpins `scenarios/c-dns-conntrack`.

## Cilium (eBPF) — requires the cilium cluster variant

```bash
.\lab.ps1 up-cilium                      # creates cluster and installs Cilium
bash platform/40-networking/install.sh    # Cilium takes over -> nodes go Ready
kubectl -n kube-system exec ds/cilium -- cilium status | grep -i KubeProxy
```

## DNS, conntrack, policy, benchmark (default cluster)

```bash
bash platform/40-networking/nodelocaldns-install.sh   # per-node DNS cache
kubectl apply -f platform/40-networking/conntrack-tuning.yaml
kubectl apply -f platform/40-networking/netpol.yaml   # ml-jobs default-deny + DNS/intra allow
kubectl apply -f platform/40-networking/iperf3.yaml   # East-West throughput
```

## Under the hood

### The pod-to-pod packet path
Pod A → its `veth` → node's network namespace → routing/encap to node B → node B's
`veth` → Pod B. On the way it hits **conntrack** (NAT/state) and, with kube-proxy,
**iptables** chains for Service load-balancing. Cilium replaces the iptables/NAT
step with **eBPF programs** attached at the socket and tc hooks: Service lookups
become O(1) eBPF map reads instead of a linear chain walk. On a node with
thousands of Services and heavy AllReduce fan-out, that overhead difference is the
whole reason big AI platforms run Cilium.

### kube-proxy replacement
Normally `kube-proxy` programs iptables/ipvs so a ClusterIP resolves to a backend
pod. Cilium's `kubeProxyReplacement` does this in eBPF — no kube-proxy pod, less
per-packet cost, and DSR/Maglev options for LB. That's why the cilium kind config
sets `kubeProxyMode: none`.

### DNS resolution + the `ndots:5` trap
A pod's `/etc/resolv.conf` has `search <ns>.svc.cluster.local svc.cluster.local
cluster.local ...` and **`options ndots:5`**. Any name with fewer than 5 dots is
tried against **every** search domain first. So `curl api.github.com` (3 dots)
becomes 4–5 lookups: `api.github.com.<ns>.svc.cluster.local` (NXDOMAIN),
`...svc.cluster.local` (NXDOMAIN), `...cluster.local` (NXDOMAIN), then finally
`api.github.com`. Multiply by thousands of workers and you've DDoSed CoreDNS.
Fixes: **FQDNs with a trailing dot** (`api.github.com.`), lower `ndots` via
`dnsConfig`, and **NodeLocal DNSCache** so most of it never leaves the node.

### conntrack
Every tracked flow = one conntrack entry. `nf_conntrack_count` climbing toward
`nf_conntrack_max` → `nf_conntrack: table full, dropping packet` → random
"network flakiness." Distributed jobs (many short-lived TCP conns) and UDP DNS
storms fill it fast. Mitigate: raise `nf_conntrack_max`, shorten timeouts
(`conntrack-tuning.yaml`), forward DNS over TCP, and let eBPF reduce per-flow
tracking.

### NetworkPolicy gotcha
A NetworkPolicy is only deny-by-default for pods it *selects*, and only for the
*directions* (`policyTypes`) it lists. The most common outage after "we added
NetworkPolicies": a default-deny **egress** policy with no DNS allow rule →
everything fails to resolve. `netpol.yaml` shows the correct DNS carve-out.

## Talking points
- eBPF vs iptables/kube-proxy and *why* it matters for AllReduce-heavy traffic.
- The exact `ndots:5` amplification math and the three fixes.
- conntrack table exhaustion: symptom, detection (`conntrack -S`, dmesg), fix.
- Hubble as "kubectl for network flows" — L3/L4/L7 + DNS + drops.
- L7 policy (CiliumNetworkPolicy) is identity-based, not IP-based — survives pod churn.

## JD coverage
Networking, DNS, "how components connect," troubleshooting at scale, structured
debugging, and durable remediation.
