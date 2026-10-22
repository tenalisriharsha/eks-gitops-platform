# Rollback runbook

Everything under `gitops/` and `sample-app/` is declarative and synced from
this repo's `main` branch, so the primary rollback path is always the same:
**fix git, then let ArgoCD (or you, manually) reconcile the cluster to
match it.** This is the GitOps answer to "a bad change reached
production" — never `kubectl edit` the live resource back by hand as the
permanent fix, or the next sync (selfHeal or otherwise) silently reverts
your manual fix back to the bad state.

## Primary path: `git revert` + sync

1. **Identify the bad commit.** `git log --oneline -- sample-app/` (or
   `gitops/`) to find the commit that introduced the change. Confirm it's
   the cause with `git show <commit>`.
2. **Revert it.**

   ```sh
   git revert <bad-commit-sha>
   git push origin main
   ```

   `git revert` creates a new commit undoing the change, rather than
   rewriting history — safe on a shared branch, and it leaves an audit
   trail of what happened and why (put that in the revert's commit
   message).
3. **Let ArgoCD pick it up.** Every Application in this repo has
   `syncPolicy.automated` set, so ArgoCD polls git (default every 3
   minutes) and syncs the reverted manifest automatically. To not wait:

   ```sh
   argocd app sync sample-app-backend
   ```

   (or whichever Application's path the revert touched — `root-app` for
   anything under `gitops/apps/`, one of `sample-app-{frontend,backend,cache}`
   for anything under `sample-app/`).
4. **Confirm it landed.**

   ```sh
   argocd app get sample-app-backend
   ./scripts/check-drift.sh
   ```

   Both should report `Synced` / `Healthy` once the revert has propagated.
   See [drift-detection.md](drift-detection.md) for what `check-drift.sh`
   does.

## Worked example: a bad backend image tag

Say `sample-app/backend/deployment.yaml` currently pins
`image: hashicorp/http-echo:1.0` (`sample-app/backend/deployment.yaml:21`),
and a commit changed it to a tag that crash-loops — `argocd app get
sample-app-backend` would show `Health: Degraded`.

```sh
# find the commit that changed the image tag
git log --oneline -- sample-app/backend/deployment.yaml
# e.g. a1b2c3d bump backend image tag

# revert it
git revert a1b2c3d
git push origin main

# force the sync instead of waiting for the next poll
argocd app sync sample-app-backend

# confirm
argocd app get sample-app-backend   # expect Sync: Synced, Health: Healthy
```

Once `Health` reports `Healthy` again, the rollback is done — no manual
`kubectl` step was needed because the Application has `selfHeal: true` and
you forced an immediate sync rather than waiting on it.

## Manual `kubectl` fallback

Use this only when ArgoCD itself is unavailable (control plane down, the
`argocd` CLI can't reach the server, or the ArgoCD Application resource
itself is what's broken) — otherwise prefer the path above, since a manual
`kubectl` fix will be reverted by the next selfHeal pass unless git also
gets fixed.

```sh
# roll a Deployment back to its previous ReplicaSet directly
kubectl -n sample-app rollout undo deployment/backend

# or pin it to a known-good image immediately, bypassing ArgoCD
kubectl -n sample-app set image deployment/backend backend=hashicorp/http-echo:1.0
```

Follow up immediately with the `git revert` above — otherwise, the moment
ArgoCD's sync loop (or `selfHeal`) notices the live state differs from git,
it reverts the manual fix back to the broken manifest, undoing the
rollback.

## If the root app-of-apps itself is broken

`gitops/argocd/root-app.yaml` is the one Application applied by hand
(`scripts/bootstrap-argocd.sh`), not managed by another Application. If a
bad change lands there (a typo in `repoURL`, a bad `targetRevision`):

```sh
git revert <bad-commit-sha>
git push origin main
kubectl apply -n argocd -f gitops/argocd/root-app.yaml
```

Re-applying it directly is correct here since nothing else manages this
one resource.
