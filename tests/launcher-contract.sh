#!/usr/bin/env bash
# Run only on a disposable development machine or hosted CI runner.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_TMP=$(mktemp -d)
trap 'rm -rf "$TASK_TMP"' EXIT
export DOCKER_CALL_LOG="$TASK_TMP/docker-calls"
mkdir "$TASK_TMP/bin"
cat > "$TASK_TMP/bin/docker" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DOCKER_CALL_LOG"
exit 0
STUB
chmod +x "$TASK_TMP/bin/docker"
export PATH="$TASK_TMP/bin:$PATH"

assert_no_docker() {
  if [ -s "$DOCKER_CALL_LOG" ]; then
    echo "Unexpected Docker invocation" >&2
    cat "$DOCKER_CALL_LOG" >&2
    exit 1
  fi
}

"$ROOT/lab.sh" help >/dev/null
assert_no_docker
if "$ROOT/lab.sh" unknown-command >/dev/null 2>&1; then
  echo "Unknown command was accepted" >&2; exit 1
fi
assert_no_docker
if env -u TX04V2_ACK_DELETE_CLUSTER "$ROOT/lab.sh" down >/dev/null 2>&1; then
  echo "Teardown without acknowledgement was accepted" >&2; exit 1
fi
assert_no_docker
if TX04V2_ACK_DELETE_CLUSTER=wrong-cluster "$ROOT/lab.sh" down >/dev/null 2>&1; then
  echo "Teardown with wrong acknowledgement was accepted" >&2; exit 1
fi
assert_no_docker
TX04V2_ACK_DELETE_CLUSTER=tx04v2 "$ROOT/lab.sh" down >/dev/null
grep -q 'kind delete cluster --name tx04v2$' "$DOCKER_CALL_LOG"
if grep -Eq 'prune|compose down|system reset' "$DOCKER_CALL_LOG"; then
  echo "Teardown invoked a broad Docker operation" >&2; exit 1
fi
: > "$DOCKER_CALL_LOG"
"$ROOT/lab.sh" grafana >/dev/null
grep -q -- '--publish 127.0.0.1:3001:3001' "$DOCKER_CALL_LOG"
: > "$DOCKER_CALL_LOG"
"$ROOT/lab.sh" prometheus >/dev/null
grep -q -- '--publish 127.0.0.1:9090:9090' "$DOCKER_CALL_LOG"
echo "Launcher contract passed without a Docker daemon."
