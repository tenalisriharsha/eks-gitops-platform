#!/usr/bin/env bash
# Installs ArgoCD onto a real EKS cluster and applies the app-of-apps root
# Application. Needs a live cluster: run
#   aws eks update-kubeconfig --name <cluster_name>
# (cluster_name is a terraform output from terraform/environments/dev) first.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
namespace="argocd"
chart_version="10.9.6"

echo "==> Checking cluster connectivity"
kubectl cluster-info >/dev/null

echo "==> Adding/updating the argo-helm repo"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null

echo "==> Installing ArgoCD ($chart_version) into namespace '$namespace'"
helm upgrade --install argocd argo/argo-cd \
  --version "$chart_version" \
  --namespace "$namespace" --create-namespace \
  --values "$repo_root/gitops/argocd/values.yaml" \
  --wait

echo "==> Applying the app-of-apps root Application"
kubectl apply -n "$namespace" -f "$repo_root/gitops/argocd/root-app.yaml"

cat <<EOF

ArgoCD is installed. Next steps:
  - Get the initial admin password:
      kubectl -n $namespace get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
  - Access the UI locally:
      kubectl -n $namespace port-forward svc/argocd-server 8080:443
      open https://localhost:8080
  - gitops/argocd/root-app.yaml's repoURL is still a placeholder — point it
    at your fork before relying on sync.
EOF
