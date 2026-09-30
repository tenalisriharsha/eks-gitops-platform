# eks-gitops-platform

Provisions a real AWS EKS cluster via Terraform — VPC, managed node groups,
and IRSA — then layers ArgoCD on top in an app-of-apps pattern to
GitOps-deploy a sample multi-service application, with drift detection and a
documented rollback procedure.

## Project Status

This project is being built in public, one phase at a time. See
[PROGRESS.md](PROGRESS.md) for the full architecture, the phased build plan,
and exactly what's done vs. what's next.

**Current status: IN_PROGRESS — Phase 1 (scaffold + Terraform foundation) complete.**

## Repository layout

```
terraform/
  modules/vpc/          VPC module: subnets, NAT/IGW, route tables, EKS tags
  environments/dev/     Root module wiring the VPC (and later EKS/IRSA) for dev
gitops/                 ArgoCD bootstrap + app-of-apps Applications (Phase 3+)
sample-app/             Sample multi-service application manifests (Phase 4+)
docs/                   Architecture notes and runbooks
scripts/                Local validation / bootstrap scripts
```

## Working locally

Terraform tests run against a **mocked** AWS provider, so no AWS account or
credentials are required to validate the modules:

```sh
./scripts/validate.sh
```

This runs `terraform fmt -check`, `terraform validate`, and `terraform test`
for every module.

## License

MIT — see [LICENSE](LICENSE).
