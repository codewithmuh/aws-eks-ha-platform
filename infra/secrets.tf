# Platform secret lives in AWS Secrets Manager (KMS-encrypted). In the cluster it
# is surfaced as the `platform-secrets` Kubernetes Secret by the Secrets Store CSI
# driver, and the charts load it via envFrom. Credentials never touch git.
resource "random_password" "jwt" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "platform" {
  name       = "${local.name}/platform-secrets"
  kms_key_id = aws_kms_key.data.arn
  tags       = local.tags
}

resource "aws_secretsmanager_secret_version" "platform" {
  secret_id = aws_secretsmanager_secret.platform.id
  secret_string = jsonencode({
    # libpq reads PGPASSWORD when the DSN has no password (see values-aws.yaml).
    PGPASSWORD = random_password.db.result
    JWT_SECRET = random_password.jwt.result
  })
}
