# ADR-0001: Use managed AWS services for the data layer

**Status:** accepted

## Context
The platform needs PostgreSQL, a Valkey cache, and a Kafka-compatible event bus,
all highly available across three zones. We can either run these inside Kubernetes
(operators like CloudNativePG, Altinity, Strimzi) or use AWS-managed equivalents.

## Decision
On AWS, run the Tier-1 stores as **managed services**: RDS PostgreSQL (Multi-AZ),
ElastiCache (Valkey engine, Multi-AZ), and Amazon MSK (3 brokers). No databases run
inside the cluster. The application stays storage-agnostic — it reads a connection
string from the environment — so the in-cluster operators remain a valid *portable
(on-prem)* profile without any code change.

## Consequences
- **+** Data-layer HA, backups, patching and failover are AWS's responsibility.
- **+** The Kubernetes layer only manages stateless services + the fenced singleton.
- **+** A DB failover becomes a clean, testable event for the fencing drill.
- **–** Cost, and less control over versions/tuning than self-hosted operators.
- **–** Portability needs the operator-based profile maintained in parallel.
