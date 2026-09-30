#!/usr/bin/env bash
# Runs fmt/validate/test for every Terraform root and module in the repo.
# Tests use a mocked AWS provider, so no AWS credentials are required.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> terraform fmt -check -recursive"
terraform fmt -check -recursive "$repo_root/terraform"

dirs=(
  "$repo_root/terraform/modules/vpc"
  "$repo_root/terraform/environments/dev"
)

for dir in "${dirs[@]}"; do
  echo "==> $dir"
  (
    cd "$dir"
    terraform init -input=false -backend=false >/dev/null
    terraform validate
    terraform test
  )
done

echo "All checks passed."
