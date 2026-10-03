# eks-gitops-platform

Provisions a real AWS EKS cluster via Terraform — VPC, managed node groups,
and IRSA — then layers ArgoCD on top in an app-of-apps pattern to
GitOps-deploy a sample multi-service application, with drift detection and a
documented rollback procedure.

## Project Status

This project is being built in public, one phase at a time. See
[PROGRESS.md](PROGRESS.md) for the full architecture, the phased build plan,
and exactly what's done vs. what's next.

**Current status: IN_PROGRESS — Phase 4 (sample app via GitOps) complete.**

## Repository layout

```
terraform/
  modules/vpc/          VPC module: subnets, NAT/IGW, route tables, EKS tags
  modules/eks/           EKS module: control plane, managed node group, OIDC provider
  modules/irsa/          IRSA module: per-service-account IAM role + trust policy
  environments/dev/     Root module wiring vpc -> eks -> irsa for dev
gitops/
  argocd/                Helm values + app-of-apps root Application
  apps/                  Child Applications, one per sample-app service
sample-app/             frontend/backend/cache manifests deployed by gitops/apps
docs/                   Architecture notes and runbooks
scripts/                Local validation / bootstrap scripts
```

## Working locally

Two independent layers, two validation scripts — neither needs real AWS
credentials or a live cluster:

```sh
./scripts/validate.sh         # terraform fmt/validate/test, mocked aws/tls providers
./scripts/validate-gitops.sh  # YAML + required-field checks, helm template render
make validate-all              # both
```

`validate.sh` runs `terraform fmt -check`, `terraform validate`, and
`terraform test` for every Terraform module and the dev environment, against
**mocked** `aws`/`tls` providers.

`validate-gitops.sh` runs the `scripts/check_manifest.rb` unit tests, then
checks YAML syntax and required fields on everything under `gitops/` and
`sample-app/` (pure Ruby stdlib, no network), then `helm template`-renders
`gitops/argocd/values.yaml` against the pinned argo-cd chart (needs network
to fetch the chart, but no cluster).

Actually installing ArgoCD needs a real EKS cluster — provision one with the
Terraform in `terraform/environments/dev`, point kubectl at it
(`aws eks update-kubeconfig --name <cluster_name>`), then run
`./scripts/bootstrap-argocd.sh`. See [gitops/README.md](gitops/README.md). It
installs the app-of-apps root `Application`, which recursively syncs the
three child Applications in `gitops/apps/` — see
[sample-app/README.md](sample-app/README.md) for what gets deployed and what
"synced" should look like.

## License

MIT — see [LICENSE](LICENSE).
