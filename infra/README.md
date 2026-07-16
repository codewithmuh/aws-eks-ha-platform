# infra/ — AWS production platform (Terraform)

Provisions the **managed-services** profile: EKS across three AZs plus RDS, ElastiCache,
MSK, Secrets Manager, KMS, ECR and S3. No databases run inside the cluster — the
data layer is AWS-managed, so its HA is handled by RDS Multi-AZ, ElastiCache Multi-AZ,
and 3-broker MSK.

```
vpc.tf          VPC: private (nodes) / public (LBs) / intra (data) subnets in 3 AZs
eks.tf          EKS cluster + managed node group + OIDC provider (for IRSA)
rds.tf          PostgreSQL — Multi-AZ, encrypted
elasticache.tf  Valkey — Multi-AZ replication group
msk.tf          Kafka — 3 brokers, one per AZ
kms.tf          Customer-managed key (rotation on) for the whole data layer
secrets.tf      Secrets Manager entry (PGPASSWORD, JWT_SECRET)
irsa.tf         Per-service IAM roles bound to Kubernetes ServiceAccounts
ecr.tf          One immutable, scanned repo per service
s3.tf           Private, encrypted object bucket
outputs.tf      Endpoints + hints to fill into charts/platform/values-aws.yaml
```

## ⚠️ Cost

This stack is **not free** — EKS, a Multi-AZ RDS, an ElastiCache group and a 3-broker
MSK cluster run into real money per day. Spin it up for a recording session, then
`make aws-destroy`. Everything is tagged `Repo=aws-eks-ha-platform` for easy auditing.

## Use

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # edit region etc.
terraform init
terraform apply                                # ~20-25 min (EKS + MSK are slow)

# Point kubectl at the cluster
$(terraform output -raw configure_kubectl)

# Wire the endpoints into the AWS Helm overlay
terraform output rds_endpoint elasticache_endpoint msk_bootstrap_brokers ecr_repository_urls
```

Then build + push images to ECR, edit `charts/platform/values-aws.yaml` with the outputs,
install the Secrets Store CSI driver + a `SecretProviderClass` for `platform-secrets`,
annotate the ServiceAccounts with the `irsa_role_arns`, and `helm upgrade --install`.
The full sequence is in [`docs/runbooks/aws-cutover.md`](../docs/runbooks/aws-cutover.md).

## Teardown

```bash
make aws-destroy
```
