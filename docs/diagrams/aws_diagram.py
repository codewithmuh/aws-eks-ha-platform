#!/usr/bin/env python3
"""AWS architecture diagram as code, using the `diagrams` library (official AWS icons).

Renders docs/images/aws-architecture.png.

Setup (once):
    brew install graphviz          # or: apt-get install graphviz
    pip install diagrams

Run (from the repo root):
    python docs/diagrams/aws_diagram.py
"""
from diagrams import Diagram, Cluster, Edge
from diagrams.onprem.client import Users
from diagrams.aws.network import Route53, ELB
from diagrams.aws.compute import EKS, ECR
from diagrams.aws.database import RDS, ElastiCache
from diagrams.aws.analytics import ManagedStreamingForKafka
from diagrams.aws.security import SecretsManager, KMS, IAMRole
from diagrams.aws.storage import S3
from diagrams.k8s.compute import Pod

graph_attr = {
    "fontsize": "22",
    "bgcolor": "white",
    "pad": "0.6",
    "nodesep": "0.7",
    "ranksep": "1.1",
    "splines": "spline",
}

with Diagram(
    "Production Kubernetes on AWS  ·  aws-eks-ha-platform",
    filename="docs/images/aws-architecture",
    outformat="png",
    direction="TB",              # vertical, top-to-bottom
    graph_attr=graph_attr,
    show=False,
):
    user = Users("Client")
    dns = Route53("Route 53")
    alb = ELB("ALB / Ingress\n(Traefik)")

    user >> dns >> alb

    with Cluster("AWS Region  —  3 Availability Zones"):

        with Cluster("EKS cluster (nodes spread across 3 AZs)"):
            login = Pod("login-service x3")
            authz = Pod("authorize-service x3")
            worker = Pod("approval-worker x2\n(fenced singleton)")

        with Cluster("Managed data layer (Multi-AZ, KMS-encrypted)"):
            rds = RDS("RDS PostgreSQL\nMulti-AZ")
            cache = ElastiCache("ElastiCache\nValkey")
            msk = ManagedStreamingForKafka("Amazon MSK\n3 brokers")

        with Cluster("Platform services"):
            secrets = SecretsManager("Secrets Manager")
            kms = KMS("KMS")
            irsa = IAMRole("IRSA roles")
            ecr = ECR("ECR")
            s3 = S3("S3")

    # request path
    alb >> Edge(color="black") >> login
    alb >> Edge(color="black") >> authz
    alb >> Edge(color="black") >> worker

    # data access
    login >> Edge(color="darkgreen") >> rds
    authz >> Edge(color="darkgreen") >> cache
    worker >> Edge(color="darkgreen") >> rds
    worker >> Edge(color="darkgreen") >> msk

    # security / identity
    worker >> Edge(color="purple", style="dashed", label="IRSA") >> secrets
    secrets >> Edge(color="purple") >> kms
