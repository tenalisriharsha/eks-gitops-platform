# docs

The architecture overview and phased build plan live in
[PROGRESS.md](../PROGRESS.md) to avoid duplication. The drift-detection
approach and rollback runbook will land here in Phase 5.

- [cluster-access.md](cluster-access.md): how the EKS API endpoint is
  exposed, the guard against an endpoint open to `0.0.0.0/0`, and how to
  reach the cluster with restricted CIDRs or a private endpoint plus SSM.

## Kubernetes version upgrades

`kubernetes_version` defaults to `1.34` (`terraform/modules/eks/variables.tf`
and `terraform/environments/dev/variables.tf`), which is in EKS standard
support. Before it was `1.31`, whose standard support ended 2025-11-26 and
whose extended support (billed at a higher hourly rate) ends 2026-11-26,
after which AWS auto-upgrades the control plane but not the managed node
group — see [EKS version lifecycle](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html).

Revisit this default again before 2026-12-02, when 1.34 leaves standard
support and starts accruing the extended-support surcharge.

For a cluster that has already been applied with an older version, do not
jump the default straight to the new value: the EKS API only allows the
control plane to move one minor version per update call, and managed node
groups are never upgraded automatically with it. For each minor version step:

1. Check the [EKS version lifecycle](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)
   page and the version-specific release notes for breaking API removals.
2. Check that the VPC CNI, `kube-proxy`, and CoreDNS add-on versions in use
   support the target control-plane version, and upgrade them first if not.
3. Set `kubernetes_version` to the next minor version only (e.g. `1.31` ->
   `1.32`) and apply, so the provider's `aws_eks_cluster` update is a single
   control-plane step.
4. Update the managed node group (new launch template/AMI release) to the
   same minor version before moving to the next step, since mixing a newer
   control plane with older nodes is only supported as a short-lived
   transition.
5. Repeat from step 1 until the control plane and node group are both on
   the target version.

This repo has never been applied to a real AWS account (see below), so no
live cluster needs this sequence yet — but the next default bump will.

## Open design decisions

These are known and deliberately not changed in code yet:

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
