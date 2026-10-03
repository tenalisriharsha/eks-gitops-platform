# gitops/apps

Child ArgoCD `Application` resources, one per service in
[`sample-app/`](../../sample-app):

- [`cache-app.yaml`](cache-app.yaml) → `sample-app/cache`
- [`backend-app.yaml`](backend-app.yaml) → `sample-app/backend`
- [`frontend-app.yaml`](frontend-app.yaml) → `sample-app/frontend`

The root app-of-apps Application (`gitops/argocd/root-app.yaml`) watches this
directory with `directory.recurse: true`, so dropping a new `*-app.yaml`
here is all it takes to onboard another service — no changes to the root
Application needed. Each child Application sets `syncOptions:
[CreateNamespace=true]` so the shared `sample-app` namespace is created on
first sync without a separate manifest.

Validate these (and everything in `sample-app/`) without a cluster via
`./scripts/validate-gitops.sh`.
