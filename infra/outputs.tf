output "region" {
  value = var.region
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "configure_kubectl" {
  description = "Point kubectl at the new cluster"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

output "rds_endpoint" {
  description = "Use as the DATABASE_URL host in charts/platform/values-aws.yaml"
  value       = aws_db_instance.postgres.address
}

output "elasticache_endpoint" {
  description = "Use as the VALKEY_URL host in values-aws.yaml"
  value       = aws_elasticache_replication_group.valkey.primary_endpoint_address
}

output "msk_bootstrap_brokers" {
  description = "Use as REDPANDA_BOOTSTRAP in values-aws.yaml"
  value       = aws_msk_cluster.this.bootstrap_brokers
}

output "ecr_repository_urls" {
  description = "Push images here; use as image.repository in values-aws.yaml"
  value       = { for k, r in aws_ecr_repository.svc : k => r.repository_url }
}

output "secrets_manager_arn" {
  value = aws_secretsmanager_secret.platform.arn
}

output "irsa_role_arns" {
  description = "Annotate each 'platform' ServiceAccount: eks.amazonaws.com/role-arn=<value>"
  value       = { for k, m in module.irsa : k => m.iam_role_arn }
}

output "s3_bucket" {
  value = aws_s3_bucket.objects.bucket
}
