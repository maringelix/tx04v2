# Debugging cheat sheet

Copy-paste one-liners grouped by domain. Most work as-is in this lab.

## Pods, events, status
```bash
kubectl get pods -A -o wide --sort-by=.metadata.creationTimestamp
kubectl describe pod <p> -n <ns> | sed -n '/Events/,$p'
kubectl get events -n <ns> --sort-by=.lastTimestamp | tail -30
kubectl get pod <p> -n <ns> -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason} exit={.status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}'
kubectl logs <p> -n <ns> --previous          # logs of the crashed instance
kubectl get pod <p> -n <ns> -o yaml | yq '.status'   # full status
```

## Nodes & capacity
```bash
kubectl get nodes -o wide
kubectl describe node <n> | grep -A8 Allocatable
kubectl describe node <n> | grep -A6 Conditions      # MemoryPressure/DiskPressure
kubectl get pods -A --field-selector spec.nodeName=<n>
kubectl get pods -A --field-selector=status.phase=Pending
```

## GPU / DCGM
```bash
kubectl get nodes -o custom-columns=NODE:.metadata.name,GPU:.status.allocatable.nvidia\\.com/gpu
kubectl exec -it <gpu-pod> -- nvidia-smi
# in Prometheus:
DCGM_FI_DEV_GPU_UTIL
DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE)   # VRAM pressure
DCGM_FI_PROF_PIPE_TENSOR_ACTIVE                                     # tensor-core use
```

## Scheduling / Volcano
```bash
kubectl get podgroups,queues -A
kubectl -n volcano-system get pods
kubectl -n volcano-system get cm volcano-scheduler-configmap -o yaml   # active plugins
kubectl get pod <p> -n <ns> -o jsonpath='{.spec.schedulerName}{"\n"}'
```

## Networking / Cilium / Hubble
```bash
kubectl -n kube-system exec ds/cilium -- cilium status
kubectl -n kube-system exec ds/cilium -- cilium status --verbose | grep -iA2 KubeProxyReplacement
kubectl -n kube-system exec ds/cilium -- cilium monitor --type drop
kubectl -n kube-system port-forward svc/hubble-ui 12000:80
# throughput
kubectl -n netbench logs job/iperf3-client
```

## DNS
```bash
kubectl -n kube-system logs deploy/coredns --tail=50
kubectl exec <p> -n <ns> -- cat /etc/resolv.conf          # ndots + search
kubectl run dnsutils --rm -it --image=busybox:1.37 -- nslookup kubernetes.default
# PromQL
sum(rate(coredns_dns_requests_total[1m]))
sum(rate(coredns_dns_responses_total{rcode="SERVFAIL"}[1m]))
```

## conntrack / sysctl (kind node = Docker container)
```bash
docker exec tx04v2-worker sh -c 'cat /proc/sys/net/netfilter/nf_conntrack_count /proc/sys/net/netfilter/nf_conntrack_max'
docker exec tx04v2-worker sh -c 'conntrack -S 2>/dev/null | head'
docker exec tx04v2-worker dmesg 2>/dev/null | grep -i conntrack | tail
```

## Images / containerd (on a node)
```bash
docker exec tx04v2-worker crictl images
docker exec tx04v2-worker sh -c 'du -sh /var/lib/containerd 2>/dev/null'
docker exec tx04v2-worker journalctl -u kubelet | grep -iE 'image|evict|diskpressure' | tail
```

## HPA / autoscaling
```bash
kubectl -n serving get hpa -w
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/serving/pods/*/llm_requests_inflight" | jq
kubectl top pods -n <ns>          # needs metrics-server
```

## Prometheus operator wiring
```bash
kubectl get servicemonitors,podmonitors,prometheusrules -A
kubectl -n monitoring get prometheus -o yaml | yq '.items[0].spec.serviceMonitorSelector'
# remember: objects need label  release: kube-prom  to be selected
```
