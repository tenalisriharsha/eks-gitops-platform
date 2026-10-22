# Daily report

A summary of what was built across the project's five phases, how it was
validated, and what's left for anyone continuing it for real. The
phase-by-phase detail (design decisions, what was considered and rejected)
lives in [PROGRESS.md](PROGRESS.md); this is the cross-phase view.

## What was built

**Infrastructure (Terraform).** A VPC module (public/private subnets across
3 AZs, IGW, NAT gateway(s), EKS subnet tags), an EKS module (control plane,
a managed node group in private subnets, an IAM OIDC provider for IRSA),
and an IRSA module (a reusable IAM role scoped to exactly one
`namespace:service-account` pair, with attachable managed policy ARNs). A
`dev` environment wires all three together. The EKS module also guards
against an API endpoint left open to `0.0.0.0/0` unless explicitly opted
into.

**GitOps (ArgoCD).** The `argo/argo-cd` Helm chart, pinned and templated
offline, installed via `scripts/bootstrap-argocd.sh`. A single app-of-apps
root `Application` recursively syncs everything under `gitops/apps/`,
which in turn deploys the sample app.

**Sample application.** Three plain-manifest Kubernetes services
(`frontend`, `backend`, `cache`) under `sample-app/`, each with its own
child ArgoCD `Application`, demonstrating a real multi-service GitOps
deploy rather than a single Hello World pod.

**Drift detection and rollback.** `scripts/check-drift.sh` reports every
Application's sync/health status for scheduled visibility (cron or CI)
beyond what `selfHeal` corrects automatically. `docs/rollback-runbook.md`
documents the `git revert` + `argocd app sync` path with a worked example,
plus a manual `kubectl` fallback.

## Test results

- `./scripts/validate.sh` — Terraform `fmt -check`, `validate`, and `test`
  for every module and the `dev` environment, against mocked `aws`/`tls`
  providers: **43 test runs, all passing**.
- `./scripts/validate-gitops.sh` — Ruby unit tests plus YAML/structural
  checks plus a `helm template` render: **26 unit tests across three test
  files** (`check_manifest_test.rb`, `helm_repo_setup_test.rb`,
  `check_drift_test.rb`), all passing, plus structural checks on every
  manifest under `gitops/` and `sample-app/`.
- `make validate-all` runs both and is the single command CI
  (`.github/workflows/validate.yml`) also runs on every push and PR.

## Known limitations

- **Nothing has been applied to a real AWS account.** Every Terraform test
  runs against a mocked provider; an actual `apply` would still be the
  first time IAM propagation, the OIDC thumbprint, and real endpoint
  access changes get exercised.
- **ArgoCD and `check-drift.sh` have never run against a live cluster.**
  Their behavior is verified with `helm template` (offline rendering) and
  unit tests against a stub `argocd` CLI, not an end-to-end sync.
- **Terraform state is local**, with no S3 backend or locking — fine for a
  single operator, not for a team.
- **The IRSA role ARN in `sample-app/backend/serviceaccount.yaml` is a
  placeholder.** The real value is an account-specific Terraform output,
  so committing a real one would tie this public repo to one AWS account.
- **The dev environment opts into an open API endpoint by default** (with
  a plan-time warning) so a fresh clone works without configuration; see
  [docs/cluster-access.md](docs/cluster-access.md) for how to lock it down.
- **`check-drift.sh`'s scheduled trigger isn't wired into CI** — a
  `schedule:` step would need real cluster credentials as GitHub secrets,
  which only exist once this is applied to an actual AWS account.

## Future ideas

- Provision `dev` in a real AWS account and exercise `bootstrap-argocd.sh`,
  `check-drift.sh`, and the rollback runbook end to end against a live
  cluster.
- Move Terraform state to S3 with DynamoDB locking once there's a team
  using this rather than a single operator.
- Wire a real `schedule:` trigger for `check-drift.sh` into CI once a
  cluster and credentials exist to target.
- Add ArgoCD notifications (Slack/email on `OutOfSync`/`Degraded`) as a
  push-based alternative to polling `check-drift.sh` on a schedule.
