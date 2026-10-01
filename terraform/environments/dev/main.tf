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

module "eks" {
  source = "../../modules/eks"

  cluster_name        = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  subnet_ids          = concat(module.vpc.public_subnet_ids_list, module.vpc.private_subnet_ids_list)
  private_subnet_ids  = module.vpc.private_subnet_ids_list
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
}

# Example IRSA role for the sample app's service account (Phase 4 wires the
# actual Kubernetes-side annotation). Add more irsa modules here as
# additional services need scoped AWS permissions.
module "irsa_sample_app" {
  source = "../../modules/irsa"

  role_name            = "${var.cluster_name}-sample-app"
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  namespace            = "sample-app"
  service_account_name = "sample-app"
}
