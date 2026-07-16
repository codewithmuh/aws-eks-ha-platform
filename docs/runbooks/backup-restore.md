# Runbook: backup & restore (into a clean environment)

The only backup that counts is one you have restored. This drill dumps the platform
database and restores it into a fresh, empty database, then checks the data.

## Local / kind
```bash
NS=platform
# 1. Back up
kubectl -n $NS exec -i deploy/postgres -- \
  pg_dump -U platform -d platform -Fc > /tmp/platform.dump

# 2. Restore into a CLEAN database (not the original)
kubectl -n $NS exec -i deploy/postgres -- psql -U platform -d postgres -c "CREATE DATABASE restore_test"
kubectl -n $NS exec -i deploy/postgres -- pg_restore -U platform -d restore_test < /tmp/platform.dump

# 3. Verify it actually restored
kubectl -n $NS exec -i deploy/postgres -- \
  psql -U platform -d restore_test -tAc "SELECT count(*) FROM approvals"
```
**Assert:** the row counts in `restore_test` match production expectations, and the
`leader_lease` / `guarded_resource` singleton rows are present.

## AWS (RDS)
- Restore is by **snapshot** into a new instance:
  `aws rds restore-db-instance-from-db-snapshot ...`
- Point a throwaway pod's `DATABASE_URL` at the restored endpoint and run the same
  verification query.
- Record wall-clock restore time — it is your real RTO, not the backup schedule.

## What to back up
| Store | Method |
|---|---|
| PostgreSQL | `pg_dump -Fc` (logical) + RDS automated snapshots (physical) |
| Valkey | none needed — cache is rebuildable; do not treat it as source of truth |
| Kafka/MSK | topics are replayable from the transactional outbox in Postgres |
