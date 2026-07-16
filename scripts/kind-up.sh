#!/usr/bin/env bash
# Spin up the local "3-AZ" Kubernetes demo: create the kind cluster, load the
# service images, deploy the in-cluster dev stores, then install the platform
# via Helm. Idempotent-ish: safe to re-run.
set -euo pipefail

CLUSTER=ha-platform
NS=platform
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== 1/5 create kind cluster (3 zones) =="
if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  kind create cluster --config deploy/kind/cluster.yaml
else
  echo "  cluster '$CLUSTER' already exists"
fi

echo "== 2/5 build + load service images =="
for name in login-service authorize-service approval-worker; do
  img="aws-eks-ha-platform-${name}:latest"
  docker build -q -t "$img" "app/${name}" >/dev/null
  kind load docker-image "$img" --name "$CLUSTER"
  echo "  loaded $img"
done

echo "== 3/5 deploy in-cluster dev stores =="
kubectl apply -f deploy/kind/stores.yaml
kubectl -n "$NS" rollout status deploy/postgres --timeout=120s
kubectl -n "$NS" rollout status deploy/valkey   --timeout=120s
kubectl -n "$NS" rollout status deploy/redpanda --timeout=180s

echo "== 4/5 helm deps + install platform =="
for c in login-service authorize-service approval-worker; do helm dependency build "charts/$c" >/dev/null; done
helm dependency build charts/platform >/dev/null
helm upgrade --install platform charts/platform \
  --namespace "$NS" \
  -f charts/platform/values-kind.yaml \
  --wait --timeout 180s

echo "== 5/5 status =="
kubectl -n "$NS" get pods -o wide
echo
echo "Port-forward to test, e.g.:"
echo "  kubectl -n $NS port-forward svc/platform-approval-worker 8083:8000 &"
echo "  curl localhost:8083/leader"
echo
echo "Then run the chaos demo:  make chaos"
