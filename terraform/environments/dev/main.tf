module "vpc" {
  source = "../../modules/vpc"

  name                 = "${var.cluster_name}-vpc"
  cidr_block           = var.vpc_cidr_block
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  single_nat_gateway   = var.single_nat_gateway
  cluster_name         = var.cluster_name
}

# module "eks" { ... }   # Phase 2
# module "irsa" { ... }  # Phase 2
