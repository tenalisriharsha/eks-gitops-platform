# Runs against a mocked AWS provider (Terraform >= 1.7 `terraform test`), so
# these tests require no AWS account or credentials. They validate the trust
# policy's service-account scoping and managed policy attachments without
# ever calling AWS.

mock_provider "aws" {}

variables {
  role_name            = "test-role"
  oidc_provider_arn    = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
  oidc_provider_url    = "oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
  namespace            = "sample-app"
  service_account_name = "sample-app"
}

run "creates_role_with_requested_name" {
  command = plan

  assert {
    condition     = aws_iam_role.this.name == var.role_name
    error_message = "role name should match var.role_name"
  }
}

run "trust_policy_scopes_to_federated_oidc_provider" {
  command = plan

  assert {
    condition     = strcontains(aws_iam_role.this.assume_role_policy, var.oidc_provider_arn)
    error_message = "trust policy must reference the OIDC provider ARN as the Federated principal"
  }

  assert {
    condition     = strcontains(aws_iam_role.this.assume_role_policy, "sts:AssumeRoleWithWebIdentity")
    error_message = "trust policy must allow sts:AssumeRoleWithWebIdentity"
  }
}

run "trust_policy_scopes_to_exact_service_account" {
  command = plan

  assert {
    condition     = strcontains(aws_iam_role.this.assume_role_policy, "system:serviceaccount:${var.namespace}:${var.service_account_name}")
    error_message = "trust policy's sub condition must scope to the exact namespace:service-account pair"
  }

  assert {
    condition     = strcontains(aws_iam_role.this.assume_role_policy, "sts.amazonaws.com")
    error_message = "trust policy's aud condition must require sts.amazonaws.com"
  }
}

run "attaches_requested_managed_policies" {
  command = plan

  variables {
    policy_arns = [
      "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
      "arn:aws:iam::aws:policy/AmazonSQSFullAccess",
    ]
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.managed) == 2
    error_message = "expected one policy attachment per entry in policy_arns"
  }
}

run "no_attachments_when_policy_arns_empty" {
  command = plan

  assert {
    condition     = length(aws_iam_role_policy_attachment.managed) == 0
    error_message = "expected no policy attachments when policy_arns is empty (the default)"
  }
}

run "rejects_empty_role_name" {
  command = plan

  variables {
    role_name = ""
  }

  expect_failures = [
    var.role_name,
  ]
}

run "rejects_overly_long_role_name" {
  command = plan

  variables {
    role_name = "this-role-name-is-way-too-long-and-exceeds-the-sixty-four-character-iam-limit"
  }

  expect_failures = [
    var.role_name,
  ]
}
