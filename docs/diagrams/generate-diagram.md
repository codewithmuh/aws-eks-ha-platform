# Generate the AWS architecture diagram

Four ways, from "one command" to "ask an AI." Pick whichever fits.

---

## Option A — Diagrams as code (real AWS icons) ✅ recommended

The committed [`aws_diagram.py`](aws_diagram.py) renders `docs/images/aws-architecture.png`
with official AWS service icons. Reproducible, version-controlled, no cloud account needed.

```bash
# one-time
brew install graphviz        # macOS   (Linux: sudo apt-get install -y graphviz)
pip install diagrams

# render
python docs/diagrams/aws_diagram.py
open docs/images/aws-architecture.png
```

Edit the Python to add/rename nodes — it's just `Node("label")` and `a >> b` edges.

---

## Option B — Generate from your Terraform (`inframap`)

Turn the actual `infra/` Terraform into a graph, so the diagram matches reality:

```bash
brew install inframap graphviz        # or download from github.com/cycloidio/inframap
inframap generate infra/ | dot -Tpng > docs/images/infra-from-terraform.png
# or from state after apply:
# terraform -chdir=infra show -json > tfplan.json && inframap generate --tfstate tfplan.json | dot -Tpng > out.png
```

---

## Option C — Ask an AI (Kiro / Amazon Q / Claude) 🤖

Paste this prompt into **Kiro**, **Amazon Q Developer CLI** (`q chat`), or any LLM. It is
self-contained, so the tool doesn't need to read the repo:

> Create an AWS architecture diagram (vertical, top-to-bottom) for a production Kubernetes
> platform called "aws-eks-ha-platform". Output it as **Python `diagrams` library code**
> (mingrammer/diagrams) that renders a PNG.
>
> Components and flow:
> - A **Client** → **Route 53** → **Application Load Balancer / Ingress (Traefik)**.
> - An **AWS Region with 3 Availability Zones** containing an **EKS cluster** whose nodes
>   are spread across the 3 AZs.
> - Three services run as Kubernetes pods in EKS: **login-service (×3)**,
>   **authorize-service (×3)**, and **approval-worker (×2, a fenced singleton)**.
> - A **managed data layer, Multi-AZ and KMS-encrypted**: **RDS PostgreSQL (Multi-AZ)**,
>   **ElastiCache (Valkey)**, and **Amazon MSK (3 brokers)**.
> - Platform services: **Secrets Manager**, **KMS**, **IRSA (IAM roles for service
>   accounts)**, **ECR**, **S3**.
> - Edges: ALB → each of the three service pods; login-service → RDS; authorize-service →
>   ElastiCache; approval-worker → RDS and MSK; approval-worker → Secrets Manager (dashed,
>   labelled "IRSA"); Secrets Manager → KMS.
> - Use `direction="TB"`, cluster boxes for "AWS Region", "EKS cluster", and "Managed data
>   layer", and save to `docs/images/aws-architecture.png`.

For a **Mermaid** diagram instead (renders on GitHub, no tools), end the prompt with:
*"Output a Mermaid `flowchart TB` instead of Python."*

---

## Option D — AWS-native, from a live account

- **AWS Application Composer** (in the console / VS Code Toolkit) — visual canvas, exports
  to CloudFormation.
- **Workload Discovery on AWS** — auto-draws diagrams from what's actually deployed in your
  account after `terraform apply`.
