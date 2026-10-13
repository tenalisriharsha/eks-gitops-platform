# The dev environment with no variables set, i.e. what an existing checkout
# plans today. It keeps the historical open API endpoint through the explicit
# allow_open_public_endpoint opt-in, and the check block must flag it on
# every plan. Mocked AWS/tls providers, no AWS account required.

mock_provider "aws" {}
mock_provider "tls" {}

run "defaults_keep_open_endpoint_via_opt_in_and_warn" {
  command = plan

  # A failing check block is a warning in plan/apply; here it proves the
  # warning fires.
  expect_failures = [
    check.eks_api_endpoint_exposure,
  ]

  assert {
    condition     = var.allow_open_public_endpoint == true
    error_message = "dev should opt in to the open endpoint by default, so existing checkouts keep planning"
  }

  assert {
    condition     = toset(output.cluster_endpoint_public_access_cidrs) == toset(["0.0.0.0/0"])
    error_message = "with the opt-in and no CIDR list, 0.0.0.0/0 should be written explicitly (matches what AWS stores today)"
  }
}

run "explicit_any_cidr_with_opt_in_also_warns" {
  command = plan

  variables {
    endpoint_public_access_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [
    check.eks_api_endpoint_exposure,
  ]
}
