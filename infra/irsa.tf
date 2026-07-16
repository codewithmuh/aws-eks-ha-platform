# IRSA — each service's Kubernetes ServiceAccount assumes a least-privilege IAM
# role via the cluster's OIDC provider. No node-wide credentials, no static keys.
# Here every service may read ONLY the platform secret and decrypt with its key.

data "aws_iam_policy_document" "secrets_read" {
  statement {
    sid       = "ReadPlatformSecret"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_secretsmanager_secret.platform.arn]
  }
  statement {
    sid       = "DecryptWithDataKey"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.data.arn]
  }
}

resource "aws_iam_policy" "secrets_read" {
  name   = "${local.name}-secrets-read"
  policy = data.aws_iam_policy_document.secrets_read.json
  tags   = local.tags
}

module "irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  for_each  = toset(local.services)
  role_name = "${local.name}-${each.value}"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["platform:${each.value}"]
    }
  }

  role_policy_arns = {
    secrets = aws_iam_policy.secrets_read.arn
  }

  tags = local.tags
}
