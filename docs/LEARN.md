# 📚 Understand this project — a guided path

Follow these steps **in order**. Each step says *what to read*, *what to run*, and *what
you should be able to explain afterwards*. Don't skip the "run it" parts — seeing it work
makes the reading click. Total time: about half a day if you go slowly.

> Rule of thumb: **concept → run it → read the code → deep dive.** Never read code before
> you've seen it run.

---

## Step 0 — What should I already know? (30 min)

You'll get the most from this if you're comfortable with:
- **Docker basics** — images, containers, `docker compose up`.
- **What Kubernetes is** — pods, deployments, services (just the idea, not expert level).
- **Basic AWS** — what EC2, VPC, and a managed database are.

If any of those are shaky, watch a 20-min primer first, then come back. You do **not** need
to be an expert — the project teaches the advanced parts.

---

## Step 1 — Get the big picture (30 min) 🖼️

**Read (in this order):**
1. [README.md](../README.md) — the top section + the architecture diagram.
2. [docs/diagrams/whiteboard-walkthrough.md](diagrams/whiteboard-walkthrough.md) — this is the
   plain-English story of the whole project. Read it slowly.
3. [docs/architecture.md](architecture.md) — the three environments table + the diagrams.

**You can now explain:** what the platform is, the three services, and *why* we move from
one server to Kubernetes on AWS.

---

## Step 2 — Run it locally, before reading any code (30 min) ▶️

```bash
cd ~/aws-eks-ha-platform
make up          # start everything on Docker Compose
make smoke       # watch a full request flow pass
make fencing-demo   # kill the leader, watch failover
```

Then poke it by hand:
```bash
curl localhost:8081/healthz          # login-service
curl localhost:8083/leader           # who is the singleton leader?
docker compose logs -f approval-worker-a   # watch the leader work
```

**You can now explain:** the app actually works, and what "the leader fails over" looks like.

---

## Step 3 — Read the application code (60 min) 🐍

The services are small on purpose. Read them in this order:
1. [app/login-service/main.py](../app/login-service/main.py) — issues JWTs (identities).
2. [app/authorize-service/main.py](../app/authorize-service/main.py) — yes/no decisions + Valkey cache.
3. [app/approval-worker/main.py](../app/approval-worker/main.py) — **the star.** Read the top
   comment block carefully, then `try_become_leader()` and `process_pending()`.
4. Then read [docs/adr/0002-fencing-tokens.md](adr/0002-fencing-tokens.md) — *why* the worker
   is built that way.

**You can now explain:** the fencing token — "a number that only goes up; the old leader's
writes hit 0 rows and it steps down." (This is Upwork application question #3.)

---

## Step 4 — How it's packaged: Docker + Helm (45 min) 📦

1. [app/login-service/Dockerfile](../app/login-service/Dockerfile) — note the non-root user.
2. [charts/platform-lib/templates/_helpers.tpl](../charts/platform-lib/templates/_helpers.tpl)
   and [_workload.tpl](../charts/platform-lib/templates/_workload.tpl) — the **library chart**:
   one place that defines the security defaults + workload shapes.
3. [docs/adr/0003-helm-library-chart.md](adr/0003-helm-library-chart.md) — why a library chart.
4. [charts/approval-worker/values.yaml](../charts/approval-worker/values.yaml) — see how a
   service picks the `fenced-singleton` archetype in a few lines.

Try it:
```bash
helm template platform charts/platform -f charts/platform/values-kind.yaml | less
```

**You can now explain:** how one library chart keeps every service secure and consistent.

---

## Step 5 — Kubernetes HA, for real (60 min) ⎈

```bash
make kind-up     # a 3-"zone" Kubernetes cluster on your laptop
make chaos       # kill the NODE hosting the leader — watch the token increment
```

**Read:** [docs/runbooks/ha-drills.md](runbooks/ha-drills.md) — the failover drills, and what
each one proves.

**You can now explain:** how the platform survives losing a whole availability zone.

---

## Step 6 — The AWS production layer (60 min) ☁️

Read the Terraform in this order (each file is short and commented):
1. [infra/vpc.tf](../infra/vpc.tf) — the network (3 zones).
2. [infra/eks.tf](../infra/eks.tf) — the Kubernetes cluster.
3. [infra/rds.tf](../infra/rds.tf), [elasticache.tf](../infra/elasticache.tf),
   [msk.tf](../infra/msk.tf) — the **managed** databases (Multi-AZ).
4. [infra/kms.tf](../infra/kms.tf) + [secrets.tf](../infra/secrets.tf) — encryption + secrets.
5. [infra/irsa.tf](../infra/irsa.tf) — per-service AWS identities (no shared keys).
6. [docs/adr/0001-managed-aws-data-layer.md](adr/0001-managed-aws-data-layer.md) — why managed.
7. [docs/runbooks/aws-cutover.md](runbooks/aws-cutover.md) — the deploy sequence.

> You don't have to `terraform apply` (it costs money). Reading + `terraform plan` is enough
> to understand it.

**You can now explain:** why the databases are AWS-managed, and how secrets/identity work
without static keys. (Upwork questions #2 and #4.)

---

## Step 7 — GitOps + operations (30 min) 🔁

1. [deploy/argocd/applicationset.yaml](../deploy/argocd/applicationset.yaml) — how Argo CD
   deploys each service from Git.
2. [docs/runbooks/backup-restore.md](runbooks/backup-restore.md) — "a backup you haven't
   restored isn't a backup."

**You can now explain:** how changes ship automatically, and how you'd recover from disaster.

---

## ✅ Final check — can you answer these? (the real test)

If you can answer all five out loud, you understand the project well enough to teach it.
These are the exact questions the Upwork job asks applicants:

1. Describe a Compose→Kubernetes migration: what broke, what you'd do differently?
   *(Hint: the two bugs we hit — the DDL race and the ErrImagePull.)*
2. How do you run secrets in HA with no static keys, and how do apps authenticate?
   *(Secrets Manager + KMS + IRSA.)*
3. A singleton must never run twice — describe your fencing design and its failure modes.
   *(Fencing token; partition / GC pause / DB failover.)*
4. Which data stores have you operated and at what scale?
   *(Postgres, Valkey, Kafka — via RDS / ElastiCache / MSK.)*
5. Your timezone and availability. *(That one's on you 🙂)*

---

## 📖 Mini-glossary

| Term | Plain meaning |
|---|---|
| **HA (high availability)** | Stays up even when a part fails. |
| **Availability Zone (AZ)** | A separate data center in a region; we use 3. |
| **Fencing token** | A number that only goes up, used to lock out a stale leader. |
| **Singleton** | A job that must run as exactly one instance at a time. |
| **IRSA** | "IAM Roles for Service Accounts" — each pod gets its own AWS permissions. |
| **Helm library chart** | Shared template other charts reuse, so nothing drifts. |
| **GitOps** | Git is the source of truth; a tool (Argo CD) syncs the cluster to it. |
| **Transactional outbox** | Write the event in the same DB transaction as the change, relay later. |
| **Idempotent** | Doing it twice has the same effect as doing it once. |
