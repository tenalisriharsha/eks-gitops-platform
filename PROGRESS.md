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

- [x] **Phase 2 — EKS cluster + IRSA** *(Night 2)*
  - EKS module (`terraform/modules/eks`): control plane, managed node group
    in private subnets, IAM OIDC identity provider for IRSA
  - IRSA module (`terraform/modules/irsa`): reusable IAM role + trust policy
    scoped to a single `namespace:service-account` pair, with attachable
    managed policy ARNs
  - Wired `module "eks"` and an example `module "irsa_sample_app"` into
    `terraform/environments/dev/main.tf` alongside the existing VPC module
  - Terraform native tests (`terraform test` with `mock_provider "aws"` and
    `mock_provider "tls"`) covering cluster/node-group wiring, IAM trust
    policies, node sizing validation, and the dev root's end-to-end plan
  - Switched IAM trust policies from `data "aws_iam_policy_document"` to
    `jsonencode(...)` — the mocked AWS provider returns a placeholder (not
    valid JSON) for a data source's computed `.json` attribute, which broke
    `aws_iam_role.assume_role_policy` validation under `terraform test`

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

## Resume point for Night 3

Start at **Phase 3**. The VPC, EKS, and IRSA modules are all in place, wired
together in `terraform/environments/dev`, and passing `terraform test` (30
assertions across 4 test suites via `./scripts/validate.sh`). Next concrete
steps:

1. Under `gitops/argocd/`, add Helm-based ArgoCD install manifests/values
   (or a `helm template` / Terraform `helm_release` approach — decide which
   and document why in PROGRESS.md).
2. Define the app-of-apps root `Application` resource (e.g.
   `gitops/argocd/root-app.yaml`) pointing at `gitops/apps/` in this repo.
3. Write a bootstrap script/doc (`scripts/bootstrap-argocd.sh` or similar)
   that installs ArgoCD onto a cluster's kubeconfig and applies the root
   Application — this is the first step that needs a real cluster
   (`aws eks update-kubeconfig`), so note clearly in docs what's testable
   locally (YAML validity, kustomize/helm template rendering) vs. what
   needs a live EKS cluster from Phase 2's Terraform.
4. Add whatever automated checks are feasible without a cluster (e.g.
   `kubeconform`/`kustomize build` validation of the manifests) and wire
   them into `scripts/validate.sh` or a new script, documenting the split
   between "runs offline" and "needs a real cluster" in README.md.
5. Keep the Terraform side green: `./scripts/validate.sh` must still pass
   after any changes.

STATUS: IN_PROGRESS
