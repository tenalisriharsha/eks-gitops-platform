# sample-app

A small three-service application deployed by ArgoCD to demonstrate the
GitOps flow end to end — not a real product, just enough wiring to prove the
pattern works. Each service is a directory of plain Kubernetes manifests
(no Helm, no build step, all public images) and gets its own ArgoCD child
`Application` in [`gitops/apps/`](../gitops/apps).

```
frontend (nginx, :80) --/api/--> backend (http-echo, :8080) --redis protocol--> cache (redis, :6379)
```

| Service    | Image                                  | Port | Manifests                             |
|------------|-----------------------------------------|------|----------------------------------------|
| `frontend` | `nginxinc/nginx-unprivileged:1.27-alpine` | 80 (proxies to 8080 internally) | [`frontend/`](frontend) |
| `backend`  | `hashicorp/http-echo:1.0`               | 8080 | [`backend/`](backend) |
| `cache`    | `redis:7-alpine`                        | 6379 | [`cache/`](cache) |

All three deploy into the `sample-app` namespace (created automatically by
each child Application's `CreateNamespace=true` sync option) and talk to each
other by Kubernetes Service DNS name — `cache`, `backend`, `frontend` — no
hardcoded IPs or Ingress required for the services to reach one another.

## frontend

Static `index.html` served by nginx from a `ConfigMap`
([`frontend/configmap.yaml`](frontend/configmap.yaml)), with nginx configured
to reverse-proxy `/api/` to `http://backend:8080/`. There's no build step —
editing the page means editing the ConfigMap and letting ArgoCD resync it.

## backend

`hashicorp/http-echo` standing in for a real API — it just echoes a fixed
string on `:8080`, which is enough to prove `frontend -> backend` connectivity
without writing and containerizing a real service for a demo app.

It runs under the `sample-app` `ServiceAccount`
([`backend/serviceaccount.yaml`](backend/serviceaccount.yaml)), which is the
exact `namespace:service-account` pair (`sample-app:sample-app`) that
`module.irsa_sample_app` in
[`terraform/environments/dev/main.tf`](../terraform/environments/dev/main.tf)
trusts via the cluster's OIDC provider. Before relying on this in a real
cluster, run `terraform apply` in `terraform/environments/dev`, then replace
the placeholder `eks.amazonaws.com/role-arn` annotation with the
`sample_app_irsa_role_arn` output — that's what lets pods under this service
account assume the IAM role without any static AWS credentials. The env vars
`CACHE_HOST=cache` / `CACHE_PORT=6379` are passed through unused by
`http-echo`, documenting where a real backend would read its Redis
connection info from.

## cache

Plain upstream `redis:7-alpine`, no persistence or auth configured — it's
disposable cache for a demo app, not a datastore anyone depends on surviving
a restart.

## What "synced" looks like

Once `gitops/argocd/root-app.yaml` is applied to a real cluster (see
[`gitops/README.md`](../gitops/README.md)), it recursively discovers
`gitops/apps/{cache,backend,frontend}-app.yaml` and creates three child
Applications. `argocd app list` should show all three as `Synced` /
`Healthy`; `kubectl get pods -n sample-app` should show one running pod per
service. Port-forward the frontend (`kubectl -n sample-app port-forward
svc/frontend 8080:80`) and load `localhost:8080` — the page itself proves
`frontend` is up, and `localhost:8080/api/` proves the proxy to `backend` is
working.
