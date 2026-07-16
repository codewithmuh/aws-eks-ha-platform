# ADR-0002: Fencing tokens, not advisory locks, for the singleton

**Status:** accepted

## Context
`approval-worker` must never run its critical section twice concurrently. Naively,
a distributed lock (a lease, a Redis lock, a Postgres advisory lock) seems enough.
It is not: a leader can be paused (GC), partitioned, or survive a DB failover and
resume believing it still holds the lock — a "zombie leader" — while a new leader is
already active. The classic split-brain double-write.

## Decision
Use a **fencing token**: a strictly monotonic integer issued on each leadership
takeover. Every state-changing write carries the writer's token; the protected
resource records the highest token it has accepted and **rejects any write with an
older token** (`WHERE last_token <= :token`). A new leader "claims" by writing its
higher token immediately on takeover, fencing the previous holder at once.

## Consequences
- **+** A zombie's writes affect zero rows and it steps down — no double-write.
- **+** Correct across the exact failure modes the role asks about: partition, GC
  pause, DB failover.
- **–** The storage must participate in the check; you cannot fence an external
  system that ignores the token.
- We therefore never claim "exactly-once"; we claim *fenced, idempotent* writes.
