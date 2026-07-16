# Tier-1 store #2: the Valkey cache plane as MANAGED ElastiCache (Valkey engine),
# Multi-AZ with automatic failover. Replaces the in-cluster Valkey from the kind demo.
resource "aws_elasticache_subnet_group" "this" {
  name       = "${local.name}-cache"
  subnet_ids = module.vpc.intra_subnets
}

resource "aws_security_group" "cache" {
  name_prefix = "${local.name}-cache-"
  description = "ElastiCache — reachable only from EKS nodes"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Valkey from EKS nodes"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

resource "aws_elasticache_replication_group" "valkey" {
  replication_group_id = "${local.name}-valkey"
  description          = "Valkey cache plane (Multi-AZ)"

  engine         = "valkey"
  engine_version = "8.0"
  node_type      = "cache.t3.micro"
  port           = 6379

  num_cache_clusters         = 2 # primary + replica in a second AZ
  automatic_failover_enabled = true
  multi_az_enabled           = true

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.cache.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = false # in-VPC only; enable for zero-trust

  tags = local.tags
}
