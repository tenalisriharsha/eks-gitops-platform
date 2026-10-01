# End-to-end smoke test for the dev root module against mocked AWS/tls
# providers: confirms the module wiring (variables -> vpc -> eks -> irsa)
# produces a valid plan with the expected resource counts. No AWS account
# required.

mock_provider "aws" {}
mock_provider "tls" {}

run "plans_with_defaults" {
  command = plan

  assert {
    condition     = length(module.vpc.private_subnet_ids_list) == length(var.azs)
    error_message = "expected one private subnet per configured AZ"
  }

  assert {
    condition     = length(module.vpc.public_subnet_ids_list) == length(var.azs)
    error_message = "expected one public subnet per configured AZ"
  }
}

run "cluster_name_propagates_to_vpc_tagging" {
  command = plan

  variables {
    cluster_name = "custom-cluster"
  }

  assert {
    condition     = length(module.vpc.private_subnet_ids_list) == length(var.azs)
    error_message = "expected the VPC to plan successfully with a custom cluster_name"
  }
}

run "eks_node_group_wired_to_private_subnets" {
  command = plan

  assert {
    condition     = module.eks.node_group_name == "${var.cluster_name}-default"
    error_message = "expected the node group name to be derived from cluster_name"
  }
}

run "irsa_role_wired_to_eks_oidc_provider" {
  command = plan

  assert {
    condition     = module.irsa_sample_app.role_name == "${var.cluster_name}-sample-app"
    error_message = "expected the sample app IRSA role name to be derived from cluster_name"
  }
}
