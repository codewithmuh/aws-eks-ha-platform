provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = "${var.project}-${var.environment}"

  # Three AZs -> genuine three-zone HA (nodes, RDS Multi-AZ, ElastiCache, 3 MSK brokers).
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  services = ["login-service", "authorize-service", "approval-worker"]

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Repo        = "aws-eks-ha-platform"
  }
}
