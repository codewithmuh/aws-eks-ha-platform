# One customer-managed KMS key encrypts the whole data layer at rest (RDS,
# ElastiCache, MSK, S3) and the platform secret. Rotation is on — the job's
# "key rotation under live traffic" drill exercises exactly this.
resource "aws_kms_key" "data" {
  description             = "${local.name} data-layer + secrets encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  tags                    = local.tags
}

resource "aws_kms_alias" "data" {
  name          = "alias/${local.name}-data"
  target_key_id = aws_kms_key.data.key_id
}
