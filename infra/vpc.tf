module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "${local.name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  # private  : EKS nodes (egress via NAT)
  # public   : load balancers / NAT gateways
  # intra    : the data layer (RDS, ElastiCache, MSK) — no route to the internet
  private_subnets = [for k, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, k + 8)]
  intra_subnets   = [for k, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, k + 12)]

  enable_nat_gateway   = true
  single_nat_gateway   = true # cost saver for the demo; set false for per-AZ NAT (full HA)
  enable_dns_hostnames = true

  # Subnet tags so EKS/AWS LB Controller can auto-discover them.
  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }

  tags = local.tags
}
