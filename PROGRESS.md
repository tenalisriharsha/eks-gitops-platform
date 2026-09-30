# Progress

## Vision

`eks-gitops-platform` provisions a real AWS EKS cluster via Terraform — VPC,
managed node groups, and IRSA (IAM Roles for Service Accounts) — then layers
ArgoCD on top in an app-of-apps pattern to GitOps-deploy a sample multi-service
application. The platform includes drift detection and a documented rollback
procedure, so it behaves like something you'd actually run, not just a demo.

## Architecture

```
                        ┌─────────────────────────────────────────┐
                        │                 AWS Account              │
                        │                                           │
                        │   ┌───────────────────────────────────┐   │
                        │   │  VPC (terraform/modules/vpc)        │   │
                        │   │  - public + private subnets x3 AZ   │   │
                        │   │  - internet gateway, NAT gateway(s) │   │
                        │   │  - route tables, EKS subnet tags    │   │
                        │   └───────────────┬───────────────────┘   │
                        │                   │                       │
                        │   ┌───────────────▼───────────────────┐   │
                        │   │  EKS cluster (terraform/modules/eks)│  │
                        │   │  - control plane                    │  │
                        │   │  - managed node groups (private)    │  │
                        │   │  - OIDC provider for IRSA           │  │
                        │   └───────────────┬───────────────────┘   │
                        │                   │                       │
                        │   ┌───────────────▼───────────────────┐   │
                        │   │  IRSA (terraform/modules/irsa)      │  │
                        │   │  - per-service-account IAM roles    │  │
                        │   └───────────────┬───────────────────┘   │
                        └───────────────────┼───────────────────────┘
                                            │ kubeconfig / OIDC trust
                        ┌───────────────────▼───────────────────────┐
                        │  ArgoCD (gitops/argocd)                    │
                        │  - installed via bootstrap Application      │
                        │  - app-of-apps root Application              │
                        └───────────────────┬───────────────────────┘
                                            │ syncs
                        ┌───────────────────▼───────────────────────┐
                        │  sample-app (gitops/apps + sample-app/)     │
                        │  - frontend, backend, cache services        │
                        │  - drift detection via ArgoCD auto-sync      │
                        │    + status checks                           │
                        └─────────────────────────────────────────────┘
```

Terraform provisions the infrastructure layer (VPC → EKS → IRSA). Once the
cluster exists, a one-time bootstrap installs ArgoCD and a single root
"app-of-apps" Application, which then owns everything below it declaratively
from the `gitops/` directory in this repo. Drift detection relies on ArgoCD's
continuous diff between desired (git) and live (cluster) state, surfaced via
`argocd app diff` / OutOfSync status, with a documented manual rollback
procedure (`git revert` + resync) for when auto-sync isn't enough.

## Phased Build Plan

- [x] **Phase 1 — Scaffold & Terraform foundation** *(Night 1)*
  - Repo scaffold: directory layout, README, PROGRESS.md, `.gitignore`, `Makefile`
  - Terraform root conventions: `versions.tf`, `providers.tf`, backend config
  - VPC module: public/private subnets across 3 AZs, IGW, NAT gateway(s),
    route tables, EKS-required subnet tags, input validation
  - Dev environment root module wiring the VPC module
  - Terraform native tests (`terraform test` with `mock_provider`, no AWS
    account required) covering the VPC module's subnet math, tagging, and
    variable validation
  - `scripts/validate.sh` — fmt check, validate, test, run locally or in CI later

- [ ] **Phase 2 — EKS cluster + IRSA**
  - EKS module: control plane, managed node groups in private subnets,
    cluster OIDC provider
  - IRSA module: reusable IAM role + trust policy per Kubernetes service account
  - Wire EKS + IRSA into the dev environment alongside the VPC
  - Terraform tests for EKS/IRSA modules (mocked, plus a real `terraform plan`
    checklist for when an AWS account is attached)

- [ ] **Phase 3 — ArgoCD bootstrap**
  - Helm-based ArgoCD install manifests/values under `gitops/argocd`
  - App-of-apps root `Application` resource
  - Bootstrap script/docs to install ArgoCD onto a fresh cluster and point it
    at this repo

- [ ] **Phase 4 — Sample multi-service app via GitOps**
  - `sample-app/`: frontend, backend, and cache services with manifests/Helm
    chart
  - Child ArgoCD `Application` resources under `gitops/apps` referencing
    `sample-app/`
  - Verify sync from a clean cluster

- [ ] **Phase 5 — Drift detection & rollback runbook**
  - Drift detection approach (ArgoCD auto-sync policy + notifications or a
    scheduled diff check)
  - Documented, tested rollback procedure (git revert + resync, plus manual
    `kubectl` fallback)
  - Final README pass, architecture diagram polish, screenshots if a UI
    component (e.g. ArgoCD UI) is actually stood up and captured

## Resume point for Night 2

Start at **Phase 2**. The VPC module and dev environment root module are in
place and passing `terraform test`. Next concrete steps:

1. Create `terraform/modules/eks/` (control plane + managed node groups +
   OIDC provider), wired to the existing `terraform/modules/vpc` outputs
   (`private_subnet_ids`, `vpc_id`).
2. Create `terraform/modules/irsa/` (assumable role per service account,
   parameterized by the EKS module's OIDC provider ARN/URL).
3. Wire both into `terraform/environments/dev/main.tf` next to the existing
   `module "vpc"` block.
4. Add `terraform test` coverage for both new modules using the same
   `mock_provider "aws"` pattern established in
   `terraform/modules/vpc/tests/vpc.tftest.hcl`.
5. Run `scripts/validate.sh` and fix any failures before moving on.

STATUS: IN_PROGRESS
