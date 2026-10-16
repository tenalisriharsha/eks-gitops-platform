# Runs against mocked aws/tls providers (Terraform >= 1.7 `terraform test`), so
# these tests require no AWS account or credentials. They validate IAM role
# wiring, node group sizing, and the OIDC provider used by the irsa module,
# without ever calling AWS.

mock_provider "aws" {}
mock_provider "tls" {}

variables {
  cluster_name                 = "test-cluster"
  subnet_ids                   = ["subnet-public-a", "subnet-public-b", "subnet-private-a", "subnet-private-b"]
  private_subnet_ids           = ["subnet-private-a", "subnet-private-b"]
  endpoint_public_access_cidrs = ["203.0.113.10/32"]
}

run "creates_cluster_and_node_group" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.name == var.cluster_name
    error_message = "cluster name should match var.cluster_name"
  }

  assert {
    condition     = aws_eks_node_group.this.cluster_name == var.cluster_name
    error_message = "node group should belong to the created cluster"
  }

  assert {
    condition     = toset(aws_eks_node_group.this.subnet_ids) == toset(var.private_subnet_ids)
    error_message = "node group must launch into the private subnets, not the full subnet_ids list"
  }
}

run "default_kubernetes_version_is_in_standard_support" {
  command = plan

  # EKS extended support costs extra and ends 26 months after a version's
  # release. Bump this alongside the variable default, not independently.
  assert {
    condition     = aws_eks_cluster.this.version == "1.34"
    error_message = "default kubernetes_version drifted from the expected supported version; update this test and docs/README.md together with the variable default"
  }

  assert {
    condition     = aws_eks_cluster.this.version != "1.31"
    error_message = "kubernetes_version must not default back to 1.31, whose EKS extended support ends 2026-11-26"
  }
}

run "kubernetes_version_passes_through" {
  command = plan

  variables {
    kubernetes_version = "1.32"
  }

  assert {
    condition     = aws_eks_cluster.this.version == "1.32"
    error_message = "cluster version should match the configured kubernetes_version"
  }
}

run "node_group_scaling_defaults" {
  command = plan

  assert {
    condition     = aws_eks_node_group.this.scaling_config[0].desired_size == 2
    error_message = "expected default desired_size of 2"
  }

  assert {
    condition     = aws_eks_node_group.this.scaling_config[0].min_size == 1
    error_message = "expected default min_size of 1"
  }

  assert {
    condition     = aws_eks_node_group.this.scaling_config[0].max_size == 3
    error_message = "expected default max_size of 3"
  }
}

run "cluster_iam_role_trusts_eks_service" {
  command = plan

  assert {
    condition     = strcontains(aws_iam_role.cluster.assume_role_policy, "eks.amazonaws.com")
    error_message = "cluster IAM role must trust the eks.amazonaws.com service principal"
  }
}

run "node_iam_role_trusts_ec2_service" {
  command = plan

  assert {
    condition     = strcontains(aws_iam_role.node.assume_role_policy, "ec2.amazonaws.com")
    error_message = "node IAM role must trust the ec2.amazonaws.com service principal"
  }
}

run "oidc_provider_created_for_irsa" {
  command = plan

  assert {
    condition     = contains(aws_iam_openid_connect_provider.this.client_id_list, "sts.amazonaws.com")
    error_message = "OIDC provider must allow sts.amazonaws.com as a client, required for IRSA"
  }
}

run "rejects_too_few_control_plane_subnets" {
  command = plan

  variables {
    subnet_ids = ["subnet-only-one"]
  }

  expect_failures = [
    var.subnet_ids,
  ]
}

run "rejects_empty_private_subnets" {
  command = plan

  variables {
    private_subnet_ids = []
  }

  expect_failures = [
    var.private_subnet_ids,
  ]
}

run "rejects_invalid_node_sizing" {
  command = plan

  variables {
    node_min_size     = 5
    node_desired_size = 2
    node_max_size     = 3
  }

  expect_failures = [
    terraform_data.validate_node_sizes,
  ]
}

run "rejects_invalid_capacity_type" {
  command = plan

  variables {
    node_capacity_type = "RESERVED"
  }

  expect_failures = [
    var.node_capacity_type,
  ]
}

# --- API endpoint exposure ---------------------------------------------------

run "rejects_open_public_endpoint_by_default" {
  command = plan

  # No CIDR list means AWS would allow 0.0.0.0/0.
  variables {
    endpoint_public_access_cidrs = []
  }

  expect_failures = [
    aws_eks_cluster.this,
  ]
}

run "rejects_explicit_ipv4_any_cidr" {
  command = plan

  variables {
    endpoint_public_access_cidrs = ["203.0.113.10/32", "0.0.0.0/0"]
  }

  expect_failures = [
    aws_eks_cluster.this,
  ]
}

run "rejects_explicit_ipv6_any_cidr" {
  command = plan

  variables {
    endpoint_public_access_cidrs = ["::/0"]
  }

  expect_failures = [
    aws_eks_cluster.this,
  ]
}

run "passes_restricted_cidrs_through" {
  command = plan

  variables {
    endpoint_public_access_cidrs = ["203.0.113.10/32", "198.51.100.0/24"]
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_public_access == true
    error_message = "public endpoint should stay enabled when a CIDR list is given"
  }

  assert {
    condition     = toset(aws_eks_cluster.this.vpc_config[0].public_access_cidrs) == toset(["203.0.113.10/32", "198.51.100.0/24"])
    error_message = "public_access_cidrs on the cluster must be exactly endpoint_public_access_cidrs"
  }

  assert {
    condition     = toset(output.cluster_endpoint_public_access_cidrs) == toset(["203.0.113.10/32", "198.51.100.0/24"])
    error_message = "cluster_endpoint_public_access_cidrs output must report the allowed CIDRs"
  }
}

run "open_endpoint_allowed_with_explicit_opt_in" {
  command = plan

  variables {
    endpoint_public_access_cidrs = []
    allow_open_public_endpoint   = true
  }

  assert {
    condition     = toset(aws_eks_cluster.this.vpc_config[0].public_access_cidrs) == toset(["0.0.0.0/0"])
    error_message = "the opt-in with no CIDR list should write 0.0.0.0/0 explicitly"
  }
}

run "private_only_endpoint_needs_no_cidrs" {
  command = plan

  variables {
    endpoint_public_access       = false
    endpoint_public_access_cidrs = []
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_public_access == false
    error_message = "public endpoint should be disabled"
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_private_access == true
    error_message = "private endpoint should stay enabled"
  }

  assert {
    condition     = output.cluster_endpoint_public_access_cidrs == null
    error_message = "no public CIDRs should be sent when the public endpoint is disabled"
  }
}

run "rejects_cidrs_with_public_endpoint_disabled" {
  command = plan

  variables {
    endpoint_public_access = false
  }

  expect_failures = [
    aws_eks_cluster.this,
  ]
}

run "rejects_both_endpoints_disabled" {
  command = plan

  variables {
    endpoint_public_access       = false
    endpoint_private_access      = false
    endpoint_public_access_cidrs = []
  }

  expect_failures = [
    aws_eks_cluster.this,
  ]
}

run "rejects_malformed_cidr" {
  command = plan

  variables {
    endpoint_public_access_cidrs = ["203.0.113.10"]
  }

  expect_failures = [
    var.endpoint_public_access_cidrs,
  ]
}
