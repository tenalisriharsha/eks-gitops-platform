# Runs against a mocked AWS provider (Terraform >= 1.7 `terraform test`), so
# these tests require no AWS account or credentials. They validate the
# module's subnet math, EKS tagging, and input validation without ever
# calling AWS.

mock_provider "aws" {}

variables {
  name = "test"
  azs  = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnet_cidrs = [
    "10.0.0.0/24",
    "10.0.1.0/24",
    "10.0.2.0/24",
  ]
  private_subnet_cidrs = [
    "10.0.100.0/24",
    "10.0.101.0/24",
    "10.0.102.0/24",
  ]
}

run "creates_one_subnet_per_az" {
  command = plan

  assert {
    condition     = length(aws_subnet.public) == length(var.azs)
    error_message = "expected one public subnet per AZ"
  }

  assert {
    condition     = length(aws_subnet.private) == length(var.azs)
    error_message = "expected one private subnet per AZ"
  }
}

run "public_subnets_map_public_ip" {
  command = plan

  assert {
    condition     = alltrue([for s in aws_subnet.public : s.map_public_ip_on_launch])
    error_message = "public subnets must auto-assign public IPs"
  }

  assert {
    condition     = alltrue([for s in aws_subnet.private : s.map_public_ip_on_launch != true])
    error_message = "private subnets must not auto-assign public IPs"
  }
}

run "single_nat_gateway_by_default" {
  command = plan

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "single_nat_gateway defaults to true, expected exactly 1 NAT gateway"
  }

  assert {
    condition     = length(aws_route_table.private) == 1
    error_message = "expected exactly 1 private route table when single_nat_gateway is true"
  }
}

run "one_nat_gateway_per_az_when_disabled" {
  command = plan

  variables {
    single_nat_gateway = false
  }

  assert {
    condition     = length(aws_nat_gateway.this) == length(var.azs)
    error_message = "expected one NAT gateway per AZ when single_nat_gateway is false"
  }

  assert {
    condition     = length(aws_route_table.private) == length(var.azs)
    error_message = "expected one private route table per AZ when single_nat_gateway is false"
  }
}

run "eks_tags_applied_when_cluster_name_set" {
  command = plan

  variables {
    cluster_name = "demo-cluster"
  }

  assert {
    condition     = alltrue([for s in aws_subnet.public : s.tags["kubernetes.io/cluster/demo-cluster"] == "shared"])
    error_message = "public subnets must carry the kubernetes.io/cluster/<name> tag when cluster_name is set"
  }

  assert {
    condition     = alltrue([for s in aws_subnet.private : s.tags["kubernetes.io/cluster/demo-cluster"] == "shared"])
    error_message = "private subnets must carry the kubernetes.io/cluster/<name> tag when cluster_name is set"
  }
}

run "eks_tags_absent_when_cluster_name_empty" {
  command = plan

  assert {
    condition     = alltrue([for s in aws_subnet.public : !contains(keys(s.tags), "kubernetes.io/cluster/")])
    error_message = "no kubernetes.io/cluster/ tag should be present when cluster_name is empty"
  }
}

run "elb_role_tags_present" {
  command = plan

  assert {
    condition     = alltrue([for s in aws_subnet.public : s.tags["kubernetes.io/role/elb"] == "1"])
    error_message = "public subnets must carry kubernetes.io/role/elb=1 for the AWS load balancer controller"
  }

  assert {
    condition     = alltrue([for s in aws_subnet.private : s.tags["kubernetes.io/role/internal-elb"] == "1"])
    error_message = "private subnets must carry kubernetes.io/role/internal-elb=1 for the AWS load balancer controller"
  }
}

run "rejects_mismatched_subnet_cidr_count" {
  command = plan

  variables {
    public_subnet_cidrs = ["10.0.0.0/24"]
  }

  expect_failures = [
    var.public_subnet_cidrs,
  ]
}

run "rejects_single_az" {
  command = plan

  variables {
    azs                  = ["us-east-1a"]
    public_subnet_cidrs  = ["10.0.0.0/24"]
    private_subnet_cidrs = ["10.0.100.0/24"]
  }

  expect_failures = [
    var.azs,
  ]
}

run "rejects_invalid_cidr" {
  command = plan

  variables {
    cidr_block = "not-a-cidr"
  }

  expect_failures = [
    var.cidr_block,
  ]
}
