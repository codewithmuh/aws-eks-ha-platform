# Runbook: HA certification drills

Run these against the kind cluster (free) or a real EKS cluster. Each drill states
what you assert. This is the "certified failover" evidence the role asks for.

## Prerequisites
```bash
make kind-up        # 3-"zone" cluster + platform deployed
```

## Drill 1 — Zone (node) loss under load
Kill the node hosting the singleton leader while traffic flows.
```bash
make chaos
```
**Assert:** a follower on a surviving zone takes leadership; the **fencing token
increases**; the processed counter keeps climbing; no double-processing.

## Drill 2 — Lease-holder kill under load
Delete the leader *pod* (not the node) repeatedly and watch takeover latency.
```bash
LEADER=$(kubectl -n platform exec -i deploy/postgres -- \
  psql -U platform -d platform -tAc "SELECT holder FROM leader_lease WHERE id=1")
kubectl -n platform delete pod "$LEADER"
```
**Assert:** new leader within ~lease TTL (10s default); token increments once.

## Drill 3 — Database failover (AWS)
On EKS, reboot RDS with failover:
```bash
aws rds reboot-db-instance --db-instance-identifier ha-platform-prod-pg --force-failover
```
**Assert:** brief write errors, then recovery; the singleton does **not** double-write
across the failover (the fencing token holds); readiness probes flip pods out and
back cleanly.

## Drill 4 — Rolling upgrade, no downtime
```bash
kubectl -n platform set image deploy/platform-login-service login-service=aws-eks-ha-platform-login-service:latest
kubectl -n platform rollout status deploy/platform-login-service
```
**Assert:** PodDisruptionBudget keeps ≥1 replica serving; smoke test stays green
throughout.

## Drill 5 — Clean-environment restore
Prove a backup actually restores (see [backup-restore.md](backup-restore.md)). A
backup you have not restored is not a backup.
