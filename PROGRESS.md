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

- [x] **Phase 4 — Sample multi-service app via GitOps** *(Night 4)*
  - `sample-app/{frontend,backend,cache}/`: plain Kubernetes manifests (no
    Helm, no build step) using public images — `nginxinc/nginx-unprivileged`
    serving a ConfigMap-mounted page that reverse-proxies `/api/` to
    `backend`, `hashicorp/http-echo` standing in for a real API, and
    `redis:7-alpine` as cache. Chose plain manifests over a Helm chart per
    service: three tiny services don't need templating, and it keeps
    `check_manifest.rb`'s plain-YAML validation working unmodified
  - `backend/serviceaccount.yaml` defines the `sample-app` ServiceAccount
    (namespace `sample-app`) that `module.irsa_sample_app` already trusts —
    the `eks.amazonaws.com/role-arn` annotation is a documented placeholder
    (same pattern as `root-app.yaml`'s `repoURL`) pointing at the
    `sample_app_irsa_role_arn` terraform output
  - Three child ArgoCD `Application` resources under `gitops/apps/`
    (`cache-app.yaml`, `backend-app.yaml`, `frontend-app.yaml`), each with
    `syncOptions: [CreateNamespace=true]` so the shared `sample-app`
    namespace needs no separate manifest; picked up automatically by the
    root app-of-apps Application via `directory.recurse: true`
  - Extended `scripts/check_manifest.rb` to also require `spec.selector` /
    `spec.template.spec.containers` on `Deployment`s and non-empty
    `spec.ports` on `Service`s, not just the existing Application checks
  - Added `scripts/tests/check_manifest_test.rb` — minitest (bundled with
    Ruby, no new dependency) black-box tests driving the real
    `check_manifest.rb` CLI against fixture YAML (valid/invalid Deployments,
    Services, Applications, multi-document streams, syntax errors) plus
    regression tests running it against every real manifest in `sample-app/`
    and `gitops/apps/`. Wired into `scripts/validate-gitops.sh` ahead of the
    existing structural checks, so `make validate-all` now runs it too
  - Verifying an actual sync still needs a real cluster (not available in
    this environment) — the manifests, Applications, and their IRSA
    cross-reference are all validated statically; a from-scratch cluster
    sync is still untested against the real ArgoCD/EKS stack

- [ ] **Phase 5 — Drift detection & rollback runbook**
  - Drift detection approach (ArgoCD auto-sync policy + notifications or a
    scheduled diff check)
  - Documented, tested rollback procedure (git revert + resync, plus manual
    `kubectl` fallback)
  - Final README pass, architecture diagram polish, screenshots if a UI
    component (e.g. ArgoCD UI) is actually stood up and captured

## Resume point for Night 5

Start at **Phase 5**. All validators are green: `./scripts/validate.sh` (30
Terraform test runs), `./scripts/validate-gitops.sh` (19 Ruby unit tests in
`scripts/tests/` + YAML/structural checks + `helm template`), and
`make validate-all` runs both. Next concrete steps:

1. Pick and document the drift-detection approach: ArgoCD's `automated` sync
   with `selfHeal: true` (already set on every Application) already
   self-heals most drift continuously — the remaining piece is a
   *detection/visibility* story for drift that selfHeal doesn't catch
   (e.g. a resource excluded from sync, or someone wanting to review before
   it's reverted). A scheduled `argocd app diff` (or `argocd app list -o
   wide` for OutOfSync status) run via cron/CI is the natural fit given this
   repo has no live cluster to wire real notifications against.
2. Write the rollback runbook in `docs/`: the primary path is `git revert`
   on the commit that introduced the unwanted change + `argocd app sync` (or
   wait for selfHeal), with a documented manual `kubectl` fallback for when
   ArgoCD itself is unavailable. Walk through a concrete example (e.g.
   reverting a bad `sample-app/backend` image tag) so it's a tested
   procedure, not just prose.
3. Final README pass across the repo (root, `gitops/`, `sample-app/`,
   `docs/`) once Phase 5 content lands.
4. This project needs real visual/CLI output for the required `docs/
   screenshots/` preview section before it can be marked COMPLETE — this
   repo has no live cluster available in this environment, so lean on
   terminal-style screenshots of real, verified command output (e.g.
   `./scripts/validate.sh`, `./scripts/validate-gitops.sh`,
   `ruby scripts/tests/check_manifest_test.rb`, `helm template` against
   `gitops/argocd/values.yaml`) rather than fabricating `kubectl`/`argocd`
   output against a cluster that doesn't exist here.
5. Keep both validators green: `make validate-all` must still pass after any
   changes.
6. Once Phase 5, the README, and the screenshots are all in, write
   `DAILY_REPORT.md` and only then set STATUS: COMPLETE.

STATUS: IN_PROGRESS
