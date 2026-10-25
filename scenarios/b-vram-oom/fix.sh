#!/usr/bin/env bash
# fix.sh — clean up Scenario B and print the durable remediations.
set -uo pipefail

echo ">> Removing the demo pods..."
kubectl -n ml-jobs delete pod cuda-oom-sim host-oom --ignore-not-found

cat <<'EOF'

>> The core insight to state in the interview:
   Kubernetes/cgroups only account HOST RAM. There is NO cgroup for GPU VRAM, so
   a CUDA OOM crashes the process (exit 1 / CrashLoopBackOff) and is INVISIBLE to
   OOMKilled, resource dashboards, and `kubectl top`. You must detect it out-of-band.

>> Durable fixes:
   1) DETECT with DCGM, not cgroups: alert on
        DCGM_FI_DEV_FB_USED / (FB_USED + FB_FREE) > 0.9
      (already shipped: platform/50-observability/prometheusrule-gpu.yaml ->
       GPUVRAMNearExhaustion). Plus scrape app-level CUDA-OOM log events.
   2) BOUND VRAM per workload with MIG (hardware-partitioned instances) or a
      fractional-GPU scheduler so one job can't consume a neighbor's VRAM.
   3) TUNE the workload: smaller batch size, gradient/activation checkpointing,
      PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True to fight fragmentation,
      mixed precision to shrink activations.
   4) SURFACE it: make the trainer log the CUDA-OOM traceback to stderr and export
      a metric/event so the platform (not just the ML engineer) can see it.

>> Cleanup done. (ml-jobs namespace kept; it's shared with platform/20-scheduling.)
EOF
