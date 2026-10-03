# gitops

ArgoCD bootstrap (`argocd/`) and the app-of-apps Application tree (`apps/`).

## argocd/

- `values.yaml` — Helm values for the `argo/argo-cd` chart, trimmed to a
  single replica per component for a small dev cluster.
- `root-app.yaml` — the app-of-apps root `Application`. ArgoCD manages this
  one manually (applied once during bootstrap); it then recursively syncs
  whatever `Application` manifests live under `apps/`.

Install onto a real cluster with `./scripts/bootstrap-argocd.sh` (needs a
kubeconfig pointed at the EKS cluster from Phase 2 — `aws eks
update-kubeconfig --name <cluster_name>`). Validate the manifests without a
cluster with `./scripts/validate-gitops.sh`.

## apps/

Child `Application` resources, one per service in `sample-app/` — see
[`apps/README.md`](apps/README.md).
