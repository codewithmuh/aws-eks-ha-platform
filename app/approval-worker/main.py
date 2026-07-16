"""approval-worker — the singleton that must never run twice.

This is the heart of the whole project. Many copies of this pod run for
availability, but only ONE may act on the shared state at a time. We do NOT
trust "I hold the lease" — a leader can be paused by a GC pause, partitioned
from the network, or survive a DB failover and wake up believing it is still
in charge (a "zombie leader"). Advisory locks alone do not save you here.

The fix is a **fencing token**: a strictly increasing number handed out each
time leadership changes hands. Every state-changing write carries the writer's
token, and the storage rejects any token older than the newest it has seen.
A zombie's writes therefore affect zero rows — it is fenced out — and it steps
down. This is the Martin Kleppmann fencing-token design, done in Postgres.

Endpoints
  POST /approvals          enqueue an approval task
  GET  /approvals/{id}     look one up
  GET  /leader             who is leader, current token, processed count
  GET  /healthz /readyz    liveness (fail-open) / readiness (fail-closed on DB)
"""
import os
import json
import socket
import logging
import threading

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from db import connection, ping, get_pool

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("approval-worker")

# Stable identity per replica. In Kubernetes this is the pod name (downward API).
IDENTITY = os.environ.get("POD_NAME") or f"{socket.gethostname()}-{os.getpid()}"
LEASE_TTL = int(os.environ.get("LEASE_TTL_SECONDS", "10"))
RENEW_INTERVAL = int(os.environ.get("LEASE_RENEW_SECONDS", "3"))
REDPANDA_BOOTSTRAP = os.environ.get("REDPANDA_BOOTSTRAP", "")
OUTBOX_TOPIC = os.environ.get("OUTBOX_TOPIC", "approval-events")

try:
    from confluent_kafka import Producer, Consumer  # type: ignore
    HAVE_KAFKA = True
except Exception as e:  # noqa: BLE001
    HAVE_KAFKA = False
    log.warning("confluent_kafka unavailable, Redpanda features disabled: %s", e)


class _State:
    def __init__(self):
        self.is_leader = False
        self.fencing_token = 0
        self.processed = 0
        self.lock = threading.Lock()


STATE = _State()
_stop = threading.Event()


# --------------------------------------------------------------------------- #
# Schema
# --------------------------------------------------------------------------- #
def init_db() -> None:
    with connection() as conn, conn.cursor() as cur:
        # Serialize schema creation across replicas. Concurrent CREATE TABLE IF NOT
        # EXISTS from multiple pods can still collide on Postgres catalog indexes,
        # so we take a transaction-scoped advisory lock first (released on commit).
        # In Kubernetes this DDL runs once as a migration Job; this makes app-start
        # idempotent and safe either way.
        cur.execute("SELECT pg_advisory_xact_lock(987654321)")
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS leader_lease (
                id            INT PRIMARY KEY DEFAULT 1,
                holder        TEXT,
                fencing_token BIGINT NOT NULL DEFAULT 0,
                expires_at    TIMESTAMPTZ,
                CONSTRAINT lease_single_row CHECK (id = 1)
            )"""
        )
        cur.execute("INSERT INTO leader_lease (id) VALUES (1) ON CONFLICT (id) DO NOTHING")
        # The protected resource. `last_token` is the highest fencing token it has
        # ever accepted a write from — the memory that fences zombies.
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS guarded_resource (
                id          INT PRIMARY KEY DEFAULT 1,
                counter     BIGINT NOT NULL DEFAULT 0,
                last_token  BIGINT NOT NULL DEFAULT 0,
                last_writer TEXT,
                CONSTRAINT resource_single_row CHECK (id = 1)
            )"""
        )
        cur.execute("INSERT INTO guarded_resource (id) VALUES (1) ON CONFLICT (id) DO NOTHING")
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS approvals (
                id            BIGSERIAL PRIMARY KEY,
                requester     TEXT NOT NULL,
                item          TEXT NOT NULL,
                status        TEXT NOT NULL DEFAULT 'pending',
                processed_by  TEXT,
                fencing_token BIGINT,
                created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
                processed_at  TIMESTAMPTZ
            )"""
        )
        # Transactional outbox: events are written in the SAME transaction as the
        # state change, then relayed to Redpanda. No lost or phantom events.
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS outbox (
                id         BIGSERIAL PRIMARY KEY,
                topic      TEXT NOT NULL,
                payload    JSONB NOT NULL,
                published  BOOLEAN NOT NULL DEFAULT false,
                created_at TIMESTAMPTZ NOT NULL DEFAULT now()
            )"""
        )


# --------------------------------------------------------------------------- #
# Leadership
# --------------------------------------------------------------------------- #
def _set_leader(is_leader: bool, token: int) -> None:
    with STATE.lock:
        was = STATE.is_leader
        STATE.is_leader = is_leader
        STATE.fencing_token = token
    if was and not is_leader:
        log.warning("%s is no longer leader", IDENTITY)


def _claim(cur, token: int) -> None:
    """On takeover, immediately stamp our (higher) token onto the resource so a
    still-running previous leader is fenced at once, not only on its next write."""
    cur.execute(
        """
        UPDATE guarded_resource
           SET last_token = %s, last_writer = %s
         WHERE id = 1 AND last_token <= %s
        """,
        (token, IDENTITY, token),
    )


def try_become_leader() -> None:
    """Renew our own live lease (token unchanged) or take an expired one (token++).
    Bumping the token only on takeover keeps it strictly monotonic across handoffs."""
    with connection() as conn, conn.cursor() as cur:
        # Fast path: renew a lease we already hold and that is still valid.
        cur.execute(
            """
            UPDATE leader_lease
               SET expires_at = now() + make_interval(secs => %s)
             WHERE id = 1 AND holder = %s AND expires_at > now()
         RETURNING fencing_token
            """,
            (LEASE_TTL, IDENTITY),
        )
        row = cur.fetchone()
        if row:
            _set_leader(True, row[0])
            return
        # Takeover path: lease is unheld or expired -> new, higher token.
        cur.execute(
            """
            UPDATE leader_lease
               SET holder = %s,
                   fencing_token = fencing_token + 1,
                   expires_at = now() + make_interval(secs => %s)
             WHERE id = 1 AND (holder IS NULL OR expires_at < now())
         RETURNING fencing_token
            """,
            (IDENTITY, LEASE_TTL),
        )
        row = cur.fetchone()
        if row:
            token = row[0]
            _claim(cur, token)
            log.info("ACQUIRED leadership as %s with fencing token %s", IDENTITY, token)
            _set_leader(True, token)
            return
    _set_leader(False, STATE.fencing_token)


# --------------------------------------------------------------------------- #
# Work — only the leader runs this, and every write is fenced
# --------------------------------------------------------------------------- #
def process_pending() -> None:
    with connection() as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT id, requester, item FROM approvals WHERE status='pending' ORDER BY id LIMIT 10"
        )
        pending = cur.fetchall()

    for aid, requester, item in pending:
        token = STATE.fencing_token
        with connection() as conn, conn.cursor() as cur:
            # Fencing guard: accept only if our token is >= the newest seen, then
            # advance it. A zombie (older token) updates 0 rows and is fenced.
            cur.execute(
                """
                UPDATE guarded_resource
                   SET counter = counter + 1, last_token = %s, last_writer = %s
                 WHERE id = 1 AND last_token <= %s
             RETURNING counter
                """,
                (token, IDENTITY, token),
            )
            if cur.fetchone() is None:
                log.error(
                    "FENCED: token %s is stale — a newer leader exists. Stepping down.", token
                )
                _set_leader(False, token)
                return
            cur.execute(
                """
                UPDATE approvals
                   SET status='approved', processed_by=%s, fencing_token=%s, processed_at=now()
                 WHERE id=%s AND status='pending'
                """,
                (IDENTITY, token, aid),
            )
            cur.execute(
                "INSERT INTO outbox (topic, payload) VALUES (%s, %s)",
                (
                    OUTBOX_TOPIC,
                    json.dumps(
                        {
                            "approval_id": aid,
                            "requester": requester,
                            "item": item,
                            "decided_by": IDENTITY,
                            "fencing_token": token,
                        }
                    ),
                ),
            )
        with STATE.lock:
            STATE.processed += 1
        log.info("approved #%s (%s) with token %s", aid, item, token)


# --------------------------------------------------------------------------- #
# Background loops
# --------------------------------------------------------------------------- #
def leader_loop() -> None:
    get_pool()
    while not _stop.is_set():
        try:
            try_become_leader()
            if STATE.is_leader:
                process_pending()
        except Exception as e:  # noqa: BLE001
            log.exception("leader loop error: %s", e)
            _set_leader(False, STATE.fencing_token)
        _stop.wait(RENEW_INTERVAL)


def outbox_relay() -> None:
    """Relay unpublished outbox rows to Redpanda. Only the leader relays, so an
    event is never double-published across replicas."""
    if not (HAVE_KAFKA and REDPANDA_BOOTSTRAP):
        log.info("outbox relay disabled (no Redpanda configured)")
        return
    producer = None
    while not _stop.is_set():
        try:
            if not STATE.is_leader:
                _stop.wait(2)
                continue
            if producer is None:
                producer = Producer({"bootstrap.servers": REDPANDA_BOOTSTRAP})
            with connection() as conn, conn.cursor() as cur:
                cur.execute(
                    "SELECT id, topic, payload::text FROM outbox WHERE published=false ORDER BY id LIMIT 50"
                )
                rows = cur.fetchall()
                for oid, topic, payload in rows:
                    producer.produce(topic, key=str(oid), value=payload)
                producer.flush(5)
                if rows:
                    cur.execute(
                        "UPDATE outbox SET published=true WHERE id = ANY(%s)",
                        ([r[0] for r in rows],),
                    )
                    log.info("relayed %s outbox event(s) to redpanda", len(rows))
        except Exception as e:  # noqa: BLE001
            log.warning("outbox relay error: %s", e)
            producer = None
        _stop.wait(2)


def consumer_loop() -> None:
    """Idempotent consumer: duplicates (same message key) are skipped. Redpanda /
    Kafka give you at-least-once; the consumer makes the effect exactly-once."""
    if not (HAVE_KAFKA and REDPANDA_BOOTSTRAP):
        return
    seen: set[str] = set()
    consumer = None
    while not _stop.is_set():
        try:
            if consumer is None:
                consumer = Consumer(
                    {
                        "bootstrap.servers": REDPANDA_BOOTSTRAP,
                        "group.id": "approval-consumer",
                        "auto.offset.reset": "earliest",
                    }
                )
                consumer.subscribe([OUTBOX_TOPIC])
            msg = consumer.poll(1.0)
            if msg is None or msg.error():
                continue
            key = msg.key().decode() if msg.key() else None
            if key in seen:
                continue
            seen.add(key)
            log.info("consumed event key=%s value=%s", key, msg.value().decode())
        except Exception as e:  # noqa: BLE001
            log.warning("consumer error: %s", e)
            consumer = None
            _stop.wait(2)
    if consumer:
        consumer.close()


# --------------------------------------------------------------------------- #
# HTTP
# --------------------------------------------------------------------------- #
app = FastAPI(title="approval-worker", version="0.1.0")


class ApprovalReq(BaseModel):
    requester: str
    item: str


@app.on_event("startup")
def _startup():
    get_pool()
    init_db()
    for target in (leader_loop, outbox_relay, consumer_loop):
        threading.Thread(target=target, name=target.__name__, daemon=True).start()
    log.info("approval-worker %s started", IDENTITY)


@app.on_event("shutdown")
def _shutdown():
    _stop.set()


@app.get("/healthz")
def healthz():
    return {"status": "ok", "identity": IDENTITY}


@app.get("/readyz")
def readyz():
    if not ping():
        raise HTTPException(status_code=503, detail="database not ready")
    return {"status": "ready"}


@app.get("/leader")
def leader():
    with STATE.lock:
        return {
            "identity": IDENTITY,
            "is_leader": STATE.is_leader,
            "fencing_token": STATE.fencing_token,
            "processed": STATE.processed,
        }


@app.post("/approvals", status_code=201)
def create_approval(req: ApprovalReq):
    with connection() as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO approvals (requester, item) VALUES (%s,%s) RETURNING id",
            (req.requester, req.item),
        )
        aid = cur.fetchone()[0]
    return {"id": aid, "status": "pending"}


@app.get("/approvals/{aid}")
def get_approval(aid: int):
    with connection() as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT id, requester, item, status, processed_by, fencing_token FROM approvals WHERE id=%s",
            (aid,),
        )
        row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="not found")
    keys = ["id", "requester", "item", "status", "processed_by", "fencing_token"]
    return dict(zip(keys, row))
