#!/usr/bin/env bash
# The Kubernetes money shot: kill the NODE (== AZ) hosting the singleton leader,
# under continuous load, and watch:
#   * a follower on a surviving zone take leadership,
#   * the fencing token increase (so the lost leader can never write again),
#   * approvals keep being processed.
#
# The leader_lease table is the authoritative source of truth, so we read it
# directly from Postgres instead of guessing from the outside.
set -euo pipefail
NS=platform
psql() { kubectl -n "$NS" exec -i deploy/postgres -- psql -U platform -d platform -tAc "$1"; }
lease() { psql "SELECT holder || '|' || fencing_token FROM leader_lease WHERE id=1"; }
counter() { psql "SELECT counter FROM guarded_resource WHERE id=1"; }

PF="" ; PF2="" ; LOAD=""
trap 'kill $PF $PF2 $LOAD 2>/dev/null || true' EXIT

# Seed a little load against the current leader so the counter is moving.
seed_load() {  # $1 = target pod, $2 = local port
  kubectl -n "$NS" port-forward "pod/$1" "$2:8000" >/dev/null 2>&1 &
  sleep 3
  for i in $(seq 1 10); do
    curl -fsS -X POST "localhost:$2/approvals" -H 'content-type: application/json' \
      -d "{\"requester\":\"load\",\"item\":\"widget-$i\"}" >/dev/null 2>&1 || true
  done
}

BEFORE=$(lease); OLD_HOLDER=${BEFORE%%|*}; OLD_TOKEN=${BEFORE##*|}
echo "== warm up load against the current leader =="
seed_load "$OLD_HOLDER" 18083 & PF=$!
sleep 6
NODE=$(kubectl -n "$NS" get pod "$OLD_HOLDER" -o jsonpath='{.spec.nodeName}')
echo "  leader pod : $OLD_HOLDER"
echo "  on node    : $NODE   (fencing token $OLD_TOKEN, processed counter $(counter))"

echo
echo "== KILL the node hosting the leader (abrupt zone loss) =="
docker stop "$NODE" >/dev/null
echo "  stopped kind node container: $NODE"

echo
echo "== wait for a new leader on a surviving zone =="
for i in $(seq 1 40); do
  NOW=$(lease); NEW_HOLDER=${NOW%%|*}; NEW_TOKEN=${NOW##*|}
  if [ "$NEW_HOLDER" != "$OLD_HOLDER" ] && [ "$NEW_TOKEN" -gt "$OLD_TOKEN" ]; then
    NEW_NODE=$(kubectl -n "$NS" get pod "$NEW_HOLDER" -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo '?')
    echo "  NEW leader : $NEW_HOLDER on node $NEW_NODE"
    printf "  \033[32m✓ fencing token %s -> %s — the lost leader is fenced out for good.\033[0m\n" "$OLD_TOKEN" "$NEW_TOKEN"
    break
  fi
  sleep 3
done

echo
echo "== confirm work continues (drive fresh load at the NEW leader) =="
C1=$(counter)
seed_load "$NEW_HOLDER" 18084 & PF2=$!
sleep 8
C2=$(counter)
echo "  processed counter: $C1 -> $C2"
[ "$C2" -gt "$C1" ] && printf "  \033[32m✓ approvals still being processed after the zone loss.\033[0m\n" || echo "  (counter did not advance — check pod logs)"

echo
echo "== restore the node =="
docker start "$NODE" >/dev/null
echo "  restarted $NODE — its old pod rejoins as a fenced follower."
