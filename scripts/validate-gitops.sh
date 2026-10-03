#!/usr/bin/env bash
# Validates the GitOps manifests without needing a live cluster:
#   1. Unit tests for scripts/check_manifest.rb itself (scripts/tests/, pure
#      Ruby stdlib + bundled minitest — no network, no cluster).
#   2. YAML syntax + required-field checks (scripts/check_manifest.rb, pure
#      Ruby stdlib — no network, no cluster).
#   3. `helm template` rendering of gitops/argocd/values.yaml against the
#      pinned argo-cd chart — needs network access to fetch the chart, but
#      not a cluster or AWS/kube credentials.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
chart_version="10.9.6"

echo "==> check_manifest.rb unit tests"
ruby "$repo_root/scripts/tests/check_manifest_test.rb"

echo "==> YAML syntax + structural checks"
manifests=$(find "$repo_root/gitops" "$repo_root/sample-app" -type f \( -name '*.yaml' -o -name '*.yml' \))
if [ -n "$manifests" ]; then
  # shellcheck disable=SC2086
  ruby "$repo_root/scripts/check_manifest.rb" $manifests
fi

echo "==> helm template: gitops/argocd/values.yaml against argo-cd $chart_version"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null
helm template argocd argo/argo-cd \
  --version "$chart_version" \
  --namespace argocd \
  --values "$repo_root/gitops/argocd/values.yaml" >/dev/null

echo "All GitOps checks passed."
