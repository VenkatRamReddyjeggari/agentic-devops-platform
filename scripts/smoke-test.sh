#!/usr/bin/env bash
# Start orders-api and check it answers. Two modes:
#
#   scripts/smoke-test.sh                 # local: run the Dockerfile's CMD (gunicorn) directly
#   SMOKE_IMAGE=orders-api:ci scripts/smoke-test.sh
#                                         # container: run the built image the way the pod does
#
# Unit tests use Flask's test client and never start a server; this proves the real
# server boots. Container mode also proves the image works under the pod's security
# settings (read-only root filesystem, non-root UID 10001, all capabilities dropped,
# no privilege escalation). No AWS needed: the checked endpoints don't touch DynamoDB.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
port="${SMOKE_PORT:-18080}"
image="${SMOKE_IMAGE:-}"
base="http://127.0.0.1:$port"
log="$(mktemp)"
container="orders-api-smoke-$$"

if [[ -n "$image" ]]; then
  # Mirror charts/orders-api/templates/deployment.yaml securityContext.
  echo "starting container: $image (read-only, uid 10001, cap-drop ALL, no-new-privileges)"
  docker run -d --name "$container" \
    --read-only --tmpfs /tmp:rw,size=16m \
    --user 10001:10001 --cap-drop ALL --security-opt no-new-privileges \
    -e ORDERS_TABLE=smoke-test -e AWS_DEFAULT_REGION=us-east-1 \
    -p "127.0.0.1:$port:8080" "$image" >/dev/null
  cleanup() { docker logs "$container" >"$log" 2>&1 || true; docker rm -f "$container" >/dev/null 2>&1 || true; rm -f "$log"; }
  alive() { [[ "$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null)" == true ]]; }
  show_log() { docker logs "$container" 2>&1 || true; }
else
  # CMD ["gunicorn", "--bind", "0.0.0.0:8080", ...] -> argv, with the port swapped.
  mapfile -t cmd < <(python3 - "$root/app/Dockerfile" "$port" <<'PY'
import json, re, sys
dockerfile, port = sys.argv[1], sys.argv[2]
m = re.search(r"^CMD\s+(\[.*\])\s*$", open(dockerfile).read(), re.M)
if not m:
    sys.exit("no exec-form CMD in Dockerfile")
for arg in json.loads(m.group(1)):
    print(re.sub(r"^0\.0\.0\.0:\d+$", f"127.0.0.1:{port}", arg))
PY
)
  echo "starting: ${cmd[*]}"
  cd "$root/app"
  ORDERS_TABLE=smoke-test AWS_DEFAULT_REGION=us-east-1 "${cmd[@]}" >"$log" 2>&1 &
  pid=$!
  cleanup() { kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; rm -f "$log"; }
  alive() { kill -0 "$pid" 2>/dev/null; }
  show_log() { cat "$log"; }
fi
trap cleanup EXIT

for _ in $(seq 1 30); do
  curl -fs "$base/healthz" >/dev/null 2>&1 && break
  alive || { echo "server exited during startup:"; show_log; exit 1; }
  sleep 1
done

fail=0
pass() { echo "  PASS  $1"; }
flunk() { echo "  FAIL  $1"; fail=1; }
check() { # name, expected status, curl args...
  local name=$1 want=$2 got
  shift 2
  got="$(curl -s -o /dev/null -w '%{http_code}' "$@")"
  if [[ "$got" == "$want" ]]; then pass "$name ($got)"; else flunk "$name (got $got, want $want)"; fi
}

check "GET /healthz" 200 "$base/healthz"
check "GET /readyz" 200 "$base/readyz"
check "GET /orders/<bad id>" 404 "$base/orders/not-a-uuid"
check "POST /orders invalid body" 400 -X POST "$base/orders" -H 'Content-Type: application/json' -d '{}'

if [[ -n "$image" ]]; then
  uid="$(docker exec "$container" id -u)"
  if [[ "$uid" == 10001 ]]; then pass "runs as uid 10001"; else flunk "runs as uid $uid, want 10001"; fi
  if docker exec "$container" sh -c 'touch /app/probe' >/dev/null 2>&1; then
    flunk "root filesystem is writable"
  else
    pass "root filesystem is read-only"
  fi
  image_user="$(docker inspect -f '{{.Config.User}}' "$image")"
  if [[ "$image_user" == 10001 ]]; then pass "image USER is 10001"; else flunk "image USER is '$image_user', want 10001"; fi
fi

if (( fail )); then echo "server log:"; show_log; exit 1; fi
show_log | grep -m1 'Starting gunicorn' || true
echo "smoke test passed"
