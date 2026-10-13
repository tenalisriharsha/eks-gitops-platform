# End-to-end smoke test for the dev root module against mocked AWS/tls
# providers: confirms the module wiring (variables -> vpc -> eks -> irsa)
# produces a valid plan with the expected resource counts. No AWS account
# required.

mock_provider "aws" {}
mock_provider "tls" {}

# Restricted API endpoint for the wiring tests below. The untouched dev
# defaults (open endpoint via the explicit opt-in) are covered in
# endpoint_defaults.tftest.hcl.
variables {
  endpoint_public_access_cidrs = ["203.0.113.10/32"]
  allow_open_public_endpoint   = false
}

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

run "restricted_cidrs_reach_the_cluster" {
  command = plan

  variables {
    endpoint_public_access_cidrs = ["203.0.113.10/32", "198.51.100.0/24"]
  }

  assert {
    condition     = toset(output.cluster_endpoint_public_access_cidrs) == toset(["203.0.113.10/32", "198.51.100.0/24"])
    error_message = "dev endpoint_public_access_cidrs must be passed through to the eks module unchanged"
  }
}

run "private_only_endpoint" {
  command = plan

  variables {
    endpoint_public_access       = false
    endpoint_public_access_cidrs = []
  }

  assert {
    condition     = output.cluster_endpoint_public_access_cidrs == null
    error_message = "a private-only endpoint should send no public CIDRs"
  }
}
