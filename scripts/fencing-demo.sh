#!/usr/bin/env bash
# The money shot on Docker Compose: kill the current leader, watch a follower
# take over, and watch the fencing token increase across the handoff.
set -euo pipefail

WORKER_A=${WORKER_A:-http://localhost:8083}
WORKER_B=${WORKER_B:-http://localhost:8084}
json() { python3 -c "import sys,json; print(json.load(sys.stdin)$1)"; }

leader_of() { curl -fsS "$1/leader"; }

echo "== current state =="
A=$(leader_of "$WORKER_A"); B=$(leader_of "$WORKER_B")
echo "  worker-a: $A"
echo "  worker-b: $B"

if [ "$(echo "$A" | json "['is_leader']")" = "True" ]; then
  LEADER_SVC="approval-worker-a"; LEADER_URL="$WORKER_A"; FOLLOWER_URL="$WORKER_B"
else
  LEADER_SVC="approval-worker-b"; LEADER_URL="$WORKER_B"; FOLLOWER_URL="$WORKER_A"
fi
OLD_TOKEN=$(leader_of "$LEADER_URL" | json "['fencing_token']")
echo
echo ">> leader is $LEADER_SVC with fencing token $OLD_TOKEN"
echo ">> killing $LEADER_SVC ..."
docker compose kill "$LEADER_SVC" >/dev/null

echo ">> waiting for the follower to take over ..."
for i in $(seq 1 20); do
  if [ "$(leader_of "$FOLLOWER_URL" | json "['is_leader']")" = "True" ]; then
    NEW_TOKEN=$(leader_of "$FOLLOWER_URL" | json "['fencing_token']")
    echo
    echo "  NEW leader token: $NEW_TOKEN  (was $OLD_TOKEN)"
    if [ "$NEW_TOKEN" -gt "$OLD_TOKEN" ]; then
      printf "\033[32m  ✓ fencing token increased on takeover — the old leader can never write again.\033[0m\n"
    fi
    echo
    echo ">> bringing the old leader back (it will rejoin as a follower, fenced out):"
    docker compose up -d "$LEADER_SVC" >/dev/null
    exit 0
  fi
  sleep 1
done
echo "follower did not take over in time" >&2; exit 1
