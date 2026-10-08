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
helm repo add --force-update argo https://argoproj.github.io/argo-helm >/dev/null
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
      http://localhost:8080  (plain HTTP: values.yaml sets server.insecure)
  - The Applications sync from github.com/tenalisriharsha/eks-gitops-platform.
    If you're running a fork, point repoURL in gitops/argocd/root-app.yaml
    and gitops/apps/*.yaml at it.
EOF
