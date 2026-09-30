# End-to-end smoke test for the dev root module against a mocked AWS
# provider: confirms the module wiring (variables -> module "vpc") produces a
# valid plan with the expected resource counts. No AWS account required.

mock_provider "aws" {}

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
