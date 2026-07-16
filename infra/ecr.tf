# One ECR repo per service. Immutable tags + scan-on-push support the digest
# pinning and vuln-scanning the security plan calls for.
resource "aws_ecr_repository" "svc" {
  for_each = toset(local.services)

  name                 = each.value
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.data.arn
  }

  tags = local.tags
}
