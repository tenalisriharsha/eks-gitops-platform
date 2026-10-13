# docs

The architecture overview and phased build plan live in
[PROGRESS.md](../PROGRESS.md) to avoid duplication. The drift-detection
approach and rollback runbook will land here in Phase 5.

- [cluster-access.md](cluster-access.md): how the EKS API endpoint is
  exposed, the guard against an endpoint open to `0.0.0.0/0`, and how to
  reach the cluster with restricted CIDRs or a private endpoint plus SSM.

## Open design decisions

These are known and deliberately not changed in code yet:

- **Kubernetes version.** `kubernetes_version` defaults to `1.31`. EKS
  standard support for 1.31 ended on 2025-11-26 and extended support (billed
  at a higher hourly rate) ends on 2026-11-26, after which AWS upgrades the
  control plane automatically
  ([EKS version lifecycle](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)).
  Bumping the default is not a drop-in change: EKS upgrades one minor
  version at a time, managed node groups are not upgraded with the control
  plane, and add-on compatibility has to be checked. It needs its own change.
- **Terraform state is local.** There is no S3 backend or state locking yet;
  see the comment in `terraform/environments/dev/backend.tf`.
- **IRSA role ARN placeholder.** `sample-app/backend/serviceaccount.yaml`
  carries `arn:aws:iam::<account-id>:role/...`. The real value depends on
  the AWS account and comes from `terraform output sample_app_irsa_role_arn`
  after an apply; committing it would tie this public repo to one account.
- **Dev opts in to an open API endpoint by default**, with a warning on every
  plan. See [cluster-access.md](cluster-access.md#the-dev-environment).
- **Nothing has been applied to a real AWS account.** All Terraform tests
  use mocked providers, so anything only a real apply would reveal (IAM
  propagation, the OIDC thumbprint, endpoint access changes) is untested.
