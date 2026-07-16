# Whiteboard walkthrough — explain this before going hands-on

Open **`architecture.excalidraw`** (drag it onto [excalidraw.com](https://excalidraw.com),
or use the VS Code *Excalidraw* extension) and talk through the three frames in order.
Each section below is your talking track — plain-language, jargon explained.

---

## Frame ① — The BEFORE (the problem)

**Say this:** "This is where almost every real project starts. The whole platform —
three services plus its databases — runs on **one server** with Docker Compose."

Point at the boxes:
- **login** — hands out identities (who are you?).
- **authorize** — makes yes/no access decisions (are you allowed?).
- **approval** — a background worker that processes approval requests.
- **PostgreSQL / Valkey / Redpanda** — the database, the cache, and the event stream.

**The punchline:** "One `docker compose up` and it all runs — great for a demo, *terrible*
for production. If that server reboots, **everything** goes down at once. There are no
zones, no failover, secrets sit in a file, and the database ports are open. This is
exactly the situation the Upwork client is in — and the job is to fix it."

> Tie-in: "This is a real senior job — 40 hrs/week, $35–60/hr. Watch what 'production-grade'
> actually means."

---

## Frame ② — The AFTER (3-zone HA on AWS)

**Say this:** "Now we migrate to Kubernetes on AWS, spread across **three Availability
Zones** — three physically separate data centers. Losing one can't take us down."

Walk the layers top to bottom:

1. **Client → Load Balancer.** "Traffic comes into an AWS load balancer, which spreads
   requests across the services."
2. **EKS cluster (the blue box).** "EKS is AWS's managed Kubernetes. Our three services
   run here as multiple copies — `×3`, `×2` — scattered across the three zones. Lose a
   zone and the survivors keep serving."
3. **The managed data layer (the green box) — this is the key AWS decision.** "We do
   **not** run our own databases. PostgreSQL becomes **RDS Multi-AZ**, the cache becomes
   **ElastiCache**, the event stream becomes **Amazon MSK**. AWS handles their replication,
   backups, and failover for us. The exact same app image works — we only change the
   connection string."
4. **Security (the purple box).** "Secrets live in **Secrets Manager**, encrypted by
   **KMS**. Each service gets its own least-privilege AWS identity via **IRSA** — no shared
   passwords, no keys in the code."

**The punchline:** "Same app, three environments — your laptop, a free local Kubernetes,
and real AWS — one set of images. That portability is the whole trick."

---

## Frame ③ — The STAR: the fencing token

This is the concept that makes the video memorable. Slow down here.

**Set up the problem:** "The approval worker must **never run twice at the same time** —
double-processing an approval is a real bug. So we run two copies but only let **one** act
at a time: the *leader*. Easy, right? Just use a lock."

**The twist:** "No. A leader can freeze — a garbage-collection pause, a network blip, or a
database failover — and while it's frozen a second copy becomes the new leader. Then the
frozen one **wakes up still thinking it's in charge**. Now you have *two* leaders. That's
the bug a plain lock can't stop — the frozen one still 'holds' the lock."

**The fix — walk the arrows:**
- Every leader gets a **number that only ever goes up** — a *fencing token*. worker-A has 7.
- worker-A writes with token 7 → the database remembers "highest token = 7." ✓
- worker-A freezes. worker-B takes over and gets token **8**, and stamps it on the database.
- The frozen worker-A wakes up and tries to write with its **old** token 7. The database
  says *"7 is less than 8 — rejected."* It updates **zero rows**, realizes it's stale, and
  steps down. **Fenced.** ✗

**The one-liner for the video:** "A number that only goes up. The old leader's writes just
bounce off. That's the whole trick — and it's why serious engineers say fencing tokens, not
just locks."

---

## Transition to hands-on

"That's the *what* and the *why*. Now let's build it — starting from that single-server
Compose stack, and we'll end by **killing a whole zone on camera** and watching the fencing
token save us." → switch to the terminal and `make up`.
