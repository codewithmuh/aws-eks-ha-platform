module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.8"

  cluster_name    = "${local.name}-eks"
  cluster_version = var.cluster_version

  # Public endpoint for convenience in the demo. For production, set this false
  # and reach the API via a bastion / VPN (the "private cluster" the job asks for).
  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets # nodes land in the 3 private (per-AZ) subnets

  # The module creates the OIDC provider used by IRSA (see irsa.tf).
  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size

      labels = { workload = "general" }
    }
  }

  tags = local.tags
}
