"""Tiny Postgres helper: a lazily-created, thread-safe connection pool with
startup retries (the database is often not ready the instant a service boots).

Kept deliberately small and dependency-light so the *infrastructure* story —
not the ORM — stays the focus of this project.
"""
import os
import time
import logging
from contextlib import contextmanager

from psycopg2.pool import ThreadedConnectionPool

log = logging.getLogger("db")

_pool: ThreadedConnectionPool | None = None


def _dsn() -> str:
    return os.environ.get(
        "DATABASE_URL",
        "postgresql://platform:platform@localhost:5432/platform",
    )


def get_pool() -> ThreadedConnectionPool:
    """Create the pool once, retrying while Postgres finishes starting up."""
    global _pool
    if _pool is not None:
        return _pool
    last_err = None
    for attempt in range(1, 31):
        try:
            _pool = ThreadedConnectionPool(minconn=1, maxconn=10, dsn=_dsn())
            log.info("postgres pool ready")
            return _pool
        except Exception as e:  # noqa: BLE001
            last_err = e
            log.warning("postgres not ready (attempt %s/30): %s", attempt, e)
            time.sleep(2)
    raise RuntimeError(f"could not connect to postgres after retries: {last_err}")


@contextmanager
def connection():
    """Borrow a connection, commit on success, roll back on error, always return it."""
    pool = get_pool()
    conn = pool.getconn()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        pool.putconn(conn)


def ping() -> bool:
    """Readiness probe helper — True only when a real query round-trips."""
    try:
        with connection() as conn, conn.cursor() as cur:
            cur.execute("SELECT 1")
            cur.fetchone()
        return True
    except Exception as e:  # noqa: BLE001
        log.warning("db ping failed: %s", e)
        return False
