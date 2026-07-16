# Runbook: deploy to AWS (EKS + managed services)

End-to-end sequence to stand up the production profile. Budget ~25-30 min (EKS + MSK
are slow to create). **This costs money** — tear down with `make aws-destroy` after.

## 1. Provision infrastructure
```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # set region, sizes
terraform init && terraform apply
$(terraform output -raw configure_kubectl)      # kubeconfig -> new cluster
```

## 2. Push images to ECR
```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=$(terraform output -raw region)
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"

for s in login-service authorize-service approval-worker; do
  docker build -t "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/$s:v0.1.0" "app/$s"
  docker push "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/$s:v0.1.0"
done
```

## 3. Secrets (Secrets Store CSI driver)
Install the CSI driver + AWS provider, then create a `SecretProviderClass` that
syncs Secrets Manager `ha-platform-prod/platform-secrets` into a Kubernetes Secret
named `platform-secrets` (keys `PGPASSWORD`, `JWT_SECRET`). The charts load it via
`envFrom`.

## 4. ServiceAccounts + IRSA
Create the three ServiceAccounts in namespace `platform`, each annotated with its
role ARN:
```bash
terraform -chdir=infra output -json irsa_role_arns
# eks.amazonaws.com/role-arn=<arn>  per service account
```

## 5. Deploy
Fill `charts/platform/values-aws.yaml` with the `terraform output` endpoints, then:
```bash
helm upgrade --install platform charts/platform \
  -n platform --create-namespace -f charts/platform/values-aws.yaml --wait
```
Or point Argo CD at [`deploy/argocd/applicationset.yaml`](../../deploy/argocd/applicationset.yaml).

## 6. Verify + certify
Run the [HA drills](ha-drills.md) against the live cluster.

## Teardown
```bash
make aws-destroy
```
