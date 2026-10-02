# gitops/apps

Child ArgoCD `Application` resources, one per service in `sample-app/`.
Populated in Phase 4 — see [PROGRESS.md](../../PROGRESS.md).

Until then, this directory is intentionally empty. The root app-of-apps
Application (`gitops/argocd/root-app.yaml`) watches this path with
`directory.recurse: true`; with no manifests here yet, ArgoCD will sync it
as an app with zero resources, which is expected.
