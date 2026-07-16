# Tier-1 store #3: the event backbone as MANAGED Amazon MSK — 3 brokers, one per
# AZ. Kafka-compatible, so the app's confluent-kafka client (used for Redpanda
# locally) connects unchanged; only REDPANDA_BOOTSTRAP changes.
resource "aws_security_group" "msk" {
  name_prefix = "${local.name}-msk-"
  description = "MSK — reachable only from EKS nodes"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Kafka plaintext from EKS nodes"
    from_port       = 9092
    to_port         = 9092
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  ingress {
    description     = "Kafka TLS from EKS nodes"
    from_port       = 9094
    to_port         = 9094
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

resource "aws_msk_cluster" "this" {
  cluster_name           = "${local.name}-msk"
  kafka_version          = "3.6.0"
  number_of_broker_nodes = 3 # one per AZ (RF=3, the job's Redpanda equivalent)

  broker_node_group_info {
    instance_type   = "kafka.t3.small"
    client_subnets  = module.vpc.intra_subnets
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = 20
      }
    }
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = aws_kms_key.data.arn
    encryption_in_transit {
      client_broker = "TLS_PLAINTEXT"
      in_cluster    = true
    }
  }

  tags = local.tags
}
