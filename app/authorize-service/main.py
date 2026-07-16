"""authorize-service — the policy decision point (PDP).

Answers "can subject X do action A on resource R?" It verifies the JWT minted by
login-service, evaluates a tiny AuthZEN-style policy, and caches the decision in
Valkey (the *cache plane*). Valkey being down degrades latency, not correctness:
we simply evaluate the policy live and keep serving.

Health model mirrors login-service: /healthz is fail-open, /readyz is fail-closed
on the Valkey dependency.
"""
import os
import hashlib
import logging

import jwt
import redis
from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("authorize-service")

JWT_SECRET = os.environ.get("JWT_SECRET", "dev-insecure-change-me")
CACHE_TTL = int(os.environ.get("DECISION_CACHE_TTL", "30"))
VALKEY_URL = os.environ.get("VALKEY_URL", "redis://localhost:6379/0")

app = FastAPI(title="authorize-service", version="0.1.0")
_r = redis.Redis.from_url(
    VALKEY_URL, socket_connect_timeout=2, socket_timeout=2, decode_responses=True
)


class AuthzReq(BaseModel):
    action: str      # "read" | "write" | "delete"
    resource: str    # e.g. "doc:42"


def decide(role: str, sub: str, action: str, resource: str) -> bool:
    """A deliberately tiny policy. Real PDPs evaluate signed, versioned policies."""
    if role == "admin":
        return True
    if action == "read":
        return True
    # non-admins may write/delete only resources they own: "<kind>:<sub>[:...]"
    kind = resource.split(":", 1)[0]
    return resource.startswith(f"{kind}:{sub}")


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/readyz")
def readyz():
    try:
        _r.ping()
    except Exception as e:  # noqa: BLE001
        raise HTTPException(status_code=503, detail=f"valkey not ready: {e}")
    return {"status": "ready"}


@app.post("/authorize")
def authorize(req: AuthzReq, authorization: str = Header(default="")):
    if not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="missing bearer token")
    token = authorization.split(" ", 1)[1]
    try:
        claims = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
    except jwt.PyJWTError as e:
        raise HTTPException(status_code=401, detail=f"invalid token: {e}")

    sub, role = claims["sub"], claims.get("role", "user")
    cache_key = "authz:" + hashlib.sha256(
        f"{sub}|{role}|{req.action}|{req.resource}".encode()
    ).hexdigest()

    # Try the cache first; a Valkey failure must not fail the request.
    try:
        cached = _r.get(cache_key)
        if cached is not None:
            return {"allow": cached == "1", "cached": True}
    except Exception as e:  # noqa: BLE001
        log.warning("valkey read failed, evaluating live: %s", e)

    allow = decide(role, sub, req.action, req.resource)
    try:
        _r.setex(cache_key, CACHE_TTL, "1" if allow else "0")
    except Exception as e:  # noqa: BLE001
        log.warning("valkey write failed: %s", e)
    return {"allow": allow, "cached": False}
