# Drift detection

"Drift" here means the live cluster state no longer matches what's
committed under `gitops/` and `sample-app/` — someone ran `kubectl edit`,
a controller mutated a resource outside ArgoCD's awareness, or a resource
was deleted by hand.

## What's already covered: selfHeal

Every Application in this repo (`gitops/argocd/root-app.yaml` and all three
under `gitops/apps/`) sets:

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```

`selfHeal: true` means ArgoCD doesn't wait for the next poll to notice drift
— it reacts to the live resource changing and reverts it to match git,
continuously. `prune: true` extends that to deletions: remove a resource's
manifest from git and ArgoCD deletes it from the cluster. For the common
case (someone or something edits a Deployment, Service, or ConfigMap this
repo manages), drift is corrected automatically, usually within seconds,
with no extra tooling.

## What selfHeal doesn't give you: visibility

selfHeal fixes drift, but it doesn't tell anyone it happened. Three gaps:

- A resource excluded from sync (e.g. via `ignoreDifferences`, or a
  cluster-scoped resource ArgoCD doesn't own) can drift indefinitely with
  no automated correction and no alert.
- selfHeal reconciles against the *live* API state; brief inconsistency
  before it reacts is invisible unless something watches for it.
- Nobody gets a record that a revert happened — useful for noticing a
  recurring source of drift (a controller fighting ArgoCD, a human habit of
  `kubectl edit`-ing instead of going through git).

`scripts/check-drift.sh` fills that gap: a point-in-time report of every
Application's `Sync`/`Health` status, meant to run on a schedule (cron or a
scheduled CI job) against a real cluster.

```sh
$ ./scripts/check-drift.sh --help
Usage: ./scripts/check-drift.sh [--diff]

Reports ArgoCD sync/health status for every Application and exits
non-zero if any is out of sync or unhealthy. Needs a live cluster with
the argocd CLI already logged in (argocd login <server>) -- see
docs/drift-detection.md.

  --diff   also run "argocd app diff <app>" for every app that isn't Synced
```

It wraps `argocd app list -o json`, prints a one-line status per
Application, and exits `1` if anything is not both `Synced` and `Healthy`
— the shape a cron job or CI step needs to alert on. `--diff` additionally
runs `argocd app diff <app>` for every out-of-sync app, which prints the
exact live-vs-git difference instead of just flagging that one exists.

Running it needs:

1. A real cluster with ArgoCD installed (`./scripts/bootstrap-argocd.sh`).
2. The `argocd` CLI, logged in once: `argocd login <server> --username admin`
   (password from `kubectl -n argocd get secret
   argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`,
   per [gitops/README.md](../gitops/README.md)).

Both are unavailable in this repo's own CI/dev environment (no AWS account
is used here — see [PROGRESS.md](../PROGRESS.md)), so `check-drift.sh`
is covered by unit tests against a stub `argocd` binary
(`scripts/tests/check_drift_test.rb`, run by `make validate-gitops`), not by
an end-to-end run against a live cluster.

## Scheduling it

The natural fit is a cron entry or a scheduled CI job on a host with
network access to the cluster and `argocd login` already run (or
credentials wired via `argocd login --sso` / an auth token):

```sh
# crontab -e
*/15 * * * * cd /path/to/eks-gitops-platform && ./scripts/check-drift.sh >> /var/log/argocd-drift.log 2>&1
```

A GitHub Actions equivalent would add a `schedule:` trigger alongside the
existing `on: push`/`pull_request` in
[.github/workflows/validate.yml](../.github/workflows/validate.yml), plus a
step that logs in with `argocd login` using a repository secret for the
server address and an auth token, then runs `./scripts/check-drift.sh`.
That's deliberately not wired up in this repo: it would need a real
cluster's address and credentials as GitHub secrets, which only exist once
someone applies the Terraform in `terraform/environments/dev` to an actual
AWS account.

## Next step if drift is found

A non-zero exit from `check-drift.sh` (or an `OutOfSync`/`Degraded` row in
its output) means something ArgoCD hasn't already corrected. From there:

- If it's still `OutOfSync` moments later, selfHeal may be failing (check
  `argocd app get <app>` for sync errors) rather than merely pending.
- If the drift is *intentional* (the live state is right and git is wrong),
  see [rollback-runbook.md](rollback-runbook.md) — update git to match, via
  a normal commit or a revert, and let ArgoCD sync.
- If the drift is *unwanted* (someone's manual change, a bug) and selfHeal
  hasn't already reverted it, `argocd app sync <app>` forces the
  reconciliation immediately instead of waiting for the next automated
  pass.
