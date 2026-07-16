"""login-service — the identity provider.

Registers users and issues short-lived JWTs. The signing secret is shared with
authorize-service; in production it comes from OpenBao / AWS Secrets Manager,
never from a baked-in default.

Health model (a Phase-1 hardening theme):
  * /healthz  — liveness: is the process alive? Independent of the DB (fail-open),
                so a brief DB blip does NOT get the pod killed and restarted.
  * /readyz   — readiness: can we actually serve? Fail-CLOSED — 503 if the DB is
                unreachable, so Kubernetes stops routing traffic here until it recovers.
"""
import os
import hashlib
import logging
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone

import jwt
import psycopg2
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from db import connection, ping, get_pool

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("login-service")

JWT_SECRET = os.environ.get("JWT_SECRET", "dev-insecure-change-me")
JWT_TTL_MIN = int(os.environ.get("JWT_TTL_MIN", "60"))


def _hash(password: str, salt: str) -> str:
    return hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), 100_000).hex()


def init_db() -> None:
    with connection() as conn, conn.cursor() as cur:
        # Transaction-scoped advisory lock so concurrent replicas can't race on DDL.
        cur.execute("SELECT pg_advisory_xact_lock(987654321)")
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS users (
                id         BIGSERIAL PRIMARY KEY,
                username   TEXT UNIQUE NOT NULL,
                salt       TEXT NOT NULL,
                pw_hash    TEXT NOT NULL,
                role       TEXT NOT NULL DEFAULT 'user',
                created_at TIMESTAMPTZ NOT NULL DEFAULT now()
            )
            """
        )


@asynccontextmanager
async def lifespan(app: FastAPI):
    get_pool()
    init_db()
    log.info("login-service ready")
    yield


app = FastAPI(title="login-service", version="0.1.0", lifespan=lifespan)


class RegisterReq(BaseModel):
    username: str
    password: str
    role: str = "user"


class LoginReq(BaseModel):
    username: str
    password: str


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/readyz")
def readyz():
    if not ping():
        raise HTTPException(status_code=503, detail="database not ready")
    return {"status": "ready"}


@app.post("/register", status_code=201)
def register(req: RegisterReq):
    salt = os.urandom(16).hex()
    pw_hash = _hash(req.password, salt)
    try:
        with connection() as conn, conn.cursor() as cur:
            cur.execute(
                "INSERT INTO users (username, salt, pw_hash, role) VALUES (%s,%s,%s,%s) RETURNING id",
                (req.username, salt, pw_hash, req.role),
            )
            uid = cur.fetchone()[0]
    except psycopg2.errors.UniqueViolation:
        raise HTTPException(status_code=409, detail="username already exists")
    return {"id": uid, "username": req.username, "role": req.role}


@app.post("/login")
def login(req: LoginReq):
    with connection() as conn, conn.cursor() as cur:
        cur.execute("SELECT id, salt, pw_hash, role FROM users WHERE username=%s", (req.username,))
        row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=401, detail="invalid credentials")
    uid, salt, pw_hash, role = row
    if _hash(req.password, salt) != pw_hash:
        raise HTTPException(status_code=401, detail="invalid credentials")
    now = datetime.now(timezone.utc)
    token = jwt.encode(
        {
            "sub": str(uid),
            "username": req.username,
            "role": role,
            "iat": now,
            "exp": now + timedelta(minutes=JWT_TTL_MIN),
        },
        JWT_SECRET,
        algorithm="HS256",
    )
    return {"access_token": token, "token_type": "bearer", "role": role}
