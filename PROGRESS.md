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

- [x] **Phase 3 — ArgoCD bootstrap** *(Night 3)*
  - `gitops/argocd/values.yaml` — Helm values for the `argo/argo-cd` chart
    (pinned to version 10.9.6 / appVersion v3.5.3), trimmed to a single
    replica per component for a dev-sized cluster
  - Chose the official Helm chart over hand-rolled manifests or vendoring
    `install.yaml`: it's maintained upstream, version-pinned, and
    `helm template` gives a real offline rendering check without needing to
    track ArgoCD's CRDs or raw manifests ourselves
  - `gitops/argocd/root-app.yaml` — the app-of-apps root `Application`,
    applied once by hand; it recursively syncs `gitops/apps` (empty until
    Phase 4) with `prune` + `selfHeal` automation
  - `scripts/bootstrap-argocd.sh` — installs the chart and applies the root
    Application onto whatever cluster the current kubeconfig points at
    (needs a real cluster — `aws eks update-kubeconfig` first)
  - `scripts/validate-gitops.sh` + `scripts/check_manifest.rb` — offline
    checks with no new dependencies: YAML syntax + required-field checks
    via Ruby's bundled YAML (Psych), plus a `helm template` render of
    `values.yaml` against the pinned chart (needs network to fetch the
    chart, but no cluster or credentials)
  - Considered `kubeconform`/`kustomize` for schema validation but neither
    was available locally and installing them wasn't worth the dependency
    for this repo's size; `kubectl --dry-run=client` turned out to still
    require live API server discovery even with `--validate=false`, so it
    couldn't fill this role either
  - Wired into `make validate-gitops` / `make validate-all` alongside the
    existing Terraform `make validate`

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

## Resume point for Night 4

Start at **Phase 4**. Terraform (`./scripts/validate.sh`, 30 assertions) and
the new GitOps checks (`./scripts/validate-gitops.sh`) both pass — `make
validate-all` runs both. Next concrete steps:

1. Build `sample-app/`: a small multi-service app (frontend, backend, cache
   is the PROGRESS.md plan — e.g. a static/simple frontend, a backend API,
   and Redis for cache) with plain Kubernetes manifests or a Helm chart per
   service. Keep it simple; the point is demonstrating the GitOps flow, not
   building a real product.
2. Add one child ArgoCD `Application` per service under `gitops/apps/`,
   each pointing at its `sample-app/<service>` path, so the root app-of-apps
   Application (`gitops/argocd/root-app.yaml`) picks them up automatically
   via `directory.recurse: true`.
3. Extend `scripts/check_manifest.rb`'s coverage (it already walks
   `sample-app/`) and confirm `./scripts/validate-gitops.sh` catches
   malformed manifests in the new service YAML.
4. Document in `sample-app/README.md` how the services relate to each other
   (ports, env vars, which IRSA role — `irsa_sample_app` from
   `terraform/environments/dev/main.tf` — a service would use if it needed
   AWS access) and what "synced" looks like once applied to a real cluster.
5. Keep both validators green: `make validate-all` must still pass after any
   changes.

STATUS: IN_PROGRESS
