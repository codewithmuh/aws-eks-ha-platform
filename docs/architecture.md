# Architecture

Three environments, **one set of container images**. The services read every
dependency from the environment, so the same image runs against local containers,
in-cluster dev stores, or managed AWS services — only connection strings change.

| Concern | Local (Compose) | kind (HA demo) | **AWS (production)** |
|---|---|---|---|
| Orchestration | Docker Compose | kind, 3 "zones" | **EKS across 3 AZs** |
| PostgreSQL | container | in-cluster pod | **RDS Multi-AZ** |
| Valkey | container | in-cluster pod | **ElastiCache Multi-AZ** |
| Kafka | Redpanda | in-cluster pod | **Amazon MSK (3 brokers)** |
| Secrets | `.env` | k8s Secret | **Secrets Manager + KMS** |
| Identity | — | — | **IRSA (per-service IAM)** |

## Services

```mermaid
flowchart LR
    U([Client]) --> LOGIN[login-service<br/>identity provider]
    U --> AUTHZ[authorize-service<br/>policy decision point]
    U --> WORKER[approval-worker<br/>workflow singleton]

    LOGIN -->|users, JWT| PG[(PostgreSQL)]
    AUTHZ -->|decision cache| VK[(Valkey)]
    AUTHZ -. verifies JWT .-> LOGIN
    WORKER -->|lease + fencing token<br/>+ outbox| PG
    WORKER -->|events| KAFKA[(Kafka / Redpanda)]
    KAFKA -->|idempotent consumer| WORKER
```

- **login-service** (`web` archetype) — registers users, issues short-lived JWTs.
- **authorize-service** (`web` archetype) — verifies the JWT, evaluates a small
  AuthZEN-style policy, caches decisions in Valkey. A Valkey outage degrades
  latency, not correctness.
- **approval-worker** (`fenced-singleton` archetype) — 2 replicas, but only the
  leader acts. A Postgres **fencing token** guarantees a stale leader can never
  write twice. Emits events via a **transactional outbox** to Kafka; consumes them
  **idempotently**.

## AWS production topology

```mermaid
flowchart TB
    user([Client])
    user --> R53[Route 53]
    R53 --> ALB[Application Load Balancer]

    subgraph REGION["AWS Region — 3 Availability Zones"]
      direction TB
      subgraph PUB["Public subnets (per-AZ)"]
        ALB
        NAT[NAT Gateway]
      end
      subgraph PRIV["Private subnets (per-AZ) — EKS nodes"]
        LOGIN[login-service x3]
        AUTHZ[authorize-service x3]
        WORKER[approval-worker x2<br/>fenced singleton]
      end
      subgraph INTRA["Intra subnets (per-AZ) — data layer, no internet"]
        RDS[(RDS PostgreSQL<br/>Multi-AZ)]
        CACHE[(ElastiCache Valkey<br/>Multi-AZ)]
        MSK[(Amazon MSK<br/>3 brokers)]
      end
      SM[Secrets Manager]
      KMS[KMS key<br/>rotation on]
      ECR[ECR]
      S3[(S3)]
    end

    ALB --> LOGIN
    ALB --> AUTHZ
    ALB --> WORKER
    LOGIN --> RDS
    WORKER --> RDS
    AUTHZ --> CACHE
    WORKER --> MSK
    LOGIN -. IRSA .-> SM
    AUTHZ -. IRSA .-> SM
    WORKER -. IRSA .-> SM
    SM --- KMS
    RDS --- KMS
    CACHE --- KMS
    MSK --- KMS
    S3 --- KMS
```

**Why managed stores?** The data layer's HA becomes AWS's responsibility (RDS
Multi-AZ synchronous standby, ElastiCache failover, MSK spread across AZs), so the
Kubernetes layer only has to keep the *stateless* services and the *fenced
singleton* healthy. It also means the singleton's hardest failure mode — a database
failover — is a first-class, testable event (see the fencing sequence below).

## The fencing token (why the singleton is safe)

```mermaid
sequenceDiagram
    participant A as worker-A (leader, token=7)
    participant DB as guarded_resource<br/>(last_token)
    participant B as worker-B

    A->>DB: write (token 7) — ok, last_token=7
    Note over A: GC pause / network partition / node dies
    B->>DB: acquire lease, token=8, claim last_token=8
    A-->>DB: write (token 7) — 7 < 8 -> 0 rows, FENCED
    Note over A: steps down, cannot corrupt state
    B->>DB: write (token 8) — ok, last_token=8
```

The token is a strictly increasing number handed out on every leadership takeover.
Every state-changing write carries it; the store rejects any token older than the
newest it has seen. Advisory locks alone cannot do this — a paused lock holder still
"holds" the lock. See [ADR-0002](adr/0002-fencing-tokens.md).
