#!/usr/bin/env bash
# Start orders-api with the exact server command from app/Dockerfile (its CMD)
# and check it answers. Unit tests use Flask's test client and never start
# gunicorn; this proves the real server boots, so server upgrades are tested too.
# No AWS needed: the checked endpoints don't touch DynamoDB.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
port="${SMOKE_PORT:-18080}"
log="$(mktemp)"

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
trap 'kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; rm -f "$log"' EXIT

base="http://127.0.0.1:$port"
for _ in $(seq 1 30); do
  curl -fs "$base/healthz" >/dev/null 2>&1 && break
  kill -0 "$pid" 2>/dev/null || { echo "server exited during startup:"; cat "$log"; exit 1; }
  sleep 1
done

fail=0
check() { # name, expected status, curl args...
  local name=$1 want=$2 got
  shift 2
  got="$(curl -s -o /dev/null -w '%{http_code}' "$@")"
  if [[ "$got" == "$want" ]]; then echo "  PASS  $name ($got)"; else echo "  FAIL  $name (got $got, want $want)"; fail=1; fi
}

check "GET /healthz" 200 "$base/healthz"
check "GET /readyz" 200 "$base/readyz"
check "GET /orders/<bad id>" 404 "$base/orders/not-a-uuid"
check "POST /orders invalid body" 400 -X POST "$base/orders" -H 'Content-Type: application/json' -d '{}'

if (( fail )); then echo "server log:"; cat "$log"; exit 1; fi
grep -m1 'Starting gunicorn' "$log" || true
echo "smoke test passed"
