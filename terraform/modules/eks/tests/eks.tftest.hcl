# Runs against mocked aws/tls providers (Terraform >= 1.7 `terraform test`), so
# these tests require no AWS account or credentials. They validate IAM role
# wiring, node group sizing, and the OIDC provider used by the irsa module,
# without ever calling AWS.

mock_provider "aws" {}
mock_provider "tls" {}

variables {
  cluster_name       = "test-cluster"
  subnet_ids         = ["subnet-public-a", "subnet-public-b", "subnet-private-a", "subnet-private-b"]
  private_subnet_ids = ["subnet-private-a", "subnet-private-b"]
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
