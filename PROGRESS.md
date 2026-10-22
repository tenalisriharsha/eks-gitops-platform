# Progress

## Vision

`eks-gitops-platform` provisions a real AWS EKS cluster via Terraform — VPC,
managed node groups, and IRSA (IAM Roles for Service Accounts) — then layers
ArgoCD on top in an app-of-apps pattern to GitOps-deploy a sample multi-service
application, with drift visibility and a documented rollback procedure;
the aim is something you'd actually run, not just a demo.

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
from the `gitops/` directory in this repo. `selfHeal: true` on every
Application corrects most drift automatically; `scripts/check-drift.sh`
adds scheduled visibility on top (sync/health status, surfaced via `argocd
app diff` / OutOfSync status — see `docs/drift-detection.md`), and
`docs/rollback-runbook.md` documents the manual rollback procedure
(`git revert` + resync, plus a `kubectl` fallback) for when auto-sync isn't
enough.

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

- [x] **Hardening — EKS API endpoint exposure**
  - The eks module rejects a public API endpoint open to `0.0.0.0/0` (an
    empty `endpoint_public_access_cidrs` list or any `/0` entry) unless
    `allow_open_public_endpoint = true`; the dev environment sets that
    opt-in by default and warns on every plan. See
    [docs/cluster-access.md](docs/cluster-access.md)
  - Other review findings kept as design decisions are listed in
    [docs/README.md](docs/README.md#open-design-decisions)

- [x] **Phase 5 — Drift detection & rollback runbook** *(Night 5)*
  - `docs/drift-detection.md`: documents what ArgoCD's `automated` sync with
    `selfHeal: true` (already set on every Application) already corrects
    automatically, and what it doesn't give you — visibility. A resource
    excluded from sync, or a human wanting a record that a revert happened,
    has no signal from selfHeal alone.
  - `scripts/check-drift.sh`: wraps `argocd app list -o json`, prints a
    one-line Sync/Health status per Application, exits non-zero if anything
    isn't `Synced`/`Healthy`, and takes an optional `--diff` to run
    `argocd app diff` on whatever's out of sync. Meant for cron or a
    scheduled CI job against a real cluster — documented but not wired into
    `.github/workflows/validate.yml`, since that would need real cluster
    credentials as GitHub secrets that only exist once this is applied to
    an actual AWS account (see `docs/drift-detection.md`'s scheduling
    section for the GitHub Actions shape once they do).
  - `scripts/tests/check_drift_test.rb`: 7 minitest cases driving the real
    `check-drift.sh` against a stub `argocd` binary on `PATH` (synced/
    healthy, out-of-sync, unhealthy, `--diff`, missing CLI, `--help`,
    unknown flag) — same no-network/no-cluster pattern as
    `helm_repo_setup_test.rb`. Wired into `scripts/validate-gitops.sh`.
  - `docs/rollback-runbook.md`: the primary `git revert` + `argocd app sync`
    path, a worked example reverting a bad `sample-app/backend` image tag,
    a manual `kubectl rollout undo`/`set image` fallback for when ArgoCD
    itself is unavailable (with the warning that it must still be followed
    by a `git revert` or the next selfHeal pass undoes it), and the
    one-off case of the root app-of-apps Application itself breaking.
  - Final README pass: root README's intro, Preview (added a 7th
    screenshot of `check-drift.sh --help`), a new "Drift detection and
    rollback" section, and Status all updated; `docs/README.md` and
    `gitops/README.md` link the two new docs.

## Resume point

All five phases are complete. `make validate-all` is green (`./scripts/validate.sh`:
43 Terraform test runs; `./scripts/validate-gitops.sh`: 26 Ruby unit tests in
`scripts/tests/` + YAML/structural checks + `helm template`). If picking
this back up:

- Nothing is applied to a real AWS account from this environment — the
  Terraform has never run `apply`, and `check-drift.sh`/`bootstrap-argocd.sh`
  have never run against a live cluster. The natural next step for someone
  continuing this project for real is provisioning dev in an actual AWS
  account and exercising the drift/rollback runbooks against it end to end,
  which would also unlock wiring a real `schedule:` trigger for
  `check-drift.sh` into CI (see `docs/drift-detection.md`).
- Open design decisions deliberately left as-is are tracked in
  [docs/README.md](docs/README.md#open-design-decisions) (local Terraform
  state, the IRSA role ARN placeholder, dev's opt-in open API endpoint).

STATUS: COMPLETE

## Build history (moved from README)

This project was built one phase at a time. See the phased build plan above
for the full architecture and what was done each night, and
[DAILY_REPORT.md](DAILY_REPORT.md) for a cross-night summary.
