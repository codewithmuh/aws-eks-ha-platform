#!/usr/bin/env bash
# End-to-end smoke test for the LOCAL (Docker Compose) stack.
# Exercises: login-service -> JWT -> authorize-service -> approval-worker fencing.
set -euo pipefail

LOGIN=${LOGIN:-http://localhost:8081}
AUTHZ=${AUTHZ:-http://localhost:8082}
WORKER_A=${WORKER_A:-http://localhost:8083}
WORKER_B=${WORKER_B:-http://localhost:8084}

pass() { printf "  \033[32m✓\033[0m %s\n" "$1"; }
fail() { printf "  \033[31m✗ %s\033[0m\n" "$1"; exit 1; }
json() { python3 -c "import sys,json; print(json.load(sys.stdin)$1)"; }

echo "== 1. Wait for services to be ready =="
for url in "$LOGIN/readyz" "$AUTHZ/readyz" "$WORKER_A/readyz" "$WORKER_B/readyz"; do
  for i in $(seq 1 40); do
    if curl -fsS "$url" >/dev/null 2>&1; then pass "ready: $url"; break; fi
    [ "$i" = 40 ] && fail "timed out waiting for $url"; sleep 2
  done
done

echo "== 2. Register + login (identity provider) =="
U="alice-$RANDOM"
curl -fsS -X POST "$LOGIN/register" -H 'content-type: application/json' \
  -d "{\"username\":\"$U\",\"password\":\"pw\",\"role\":\"user\"}" >/dev/null
pass "registered $U"
TOKEN=$(curl -fsS -X POST "$LOGIN/login" -H 'content-type: application/json' \
  -d "{\"username\":\"$U\",\"password\":\"pw\"}" | json "['access_token']")
[ -n "$TOKEN" ] && pass "got JWT" || fail "no token"

echo "== 3. Authorize (policy decision point + Valkey cache) =="
ALLOW=$(curl -fsS -X POST "$AUTHZ/authorize" -H "authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' -d '{"action":"read","resource":"doc:1"}' | json "['allow']")
[ "$ALLOW" = "True" ] && pass "read allowed" || fail "read should be allowed"
DENY=$(curl -fsS -X POST "$AUTHZ/authorize" -H "authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' -d '{"action":"delete","resource":"doc:999999"}' | json "['allow']")
[ "$DENY" = "False" ] && pass "delete on foreign resource denied" || fail "delete should be denied"

echo "== 4. Exactly one leader among the two workers =="
LA=$(curl -fsS "$WORKER_A/leader" | json "['is_leader']")
LB=$(curl -fsS "$WORKER_B/leader" | json "['is_leader']")
echo "     worker-a is_leader=$LA  worker-b is_leader=$LB"
if { [ "$LA" = "True" ] && [ "$LB" = "False" ]; } || { [ "$LA" = "False" ] && [ "$LB" = "True" ]; }; then
  pass "exactly one leader"
else
  fail "expected exactly one leader (got a=$LA b=$LB)"
fi

echo "== 5. Enqueue an approval and watch the leader process it =="
AID=$(curl -fsS -X POST "$WORKER_A/approvals" -H 'content-type: application/json' \
  -d "{\"requester\":\"$U\",\"item\":\"laptop\"}" | json "['id']")
pass "enqueued approval #$AID"
for i in $(seq 1 15); do
  ST=$(curl -fsS "$WORKER_A/approvals/$AID" | json "['status']")
  if [ "$ST" = "approved" ]; then
    BY=$(curl -fsS "$WORKER_A/approvals/$AID" | json "['processed_by']")
    TOK=$(curl -fsS "$WORKER_A/approvals/$AID" | json "['fencing_token']")
    pass "approval #$AID approved by $BY (fencing token $TOK)"
    break
  fi
  [ "$i" = 15 ] && fail "approval #$AID never processed"; sleep 2
done

echo
printf "\033[32mALL GOOD — the platform works end to end.\033[0m\n"
