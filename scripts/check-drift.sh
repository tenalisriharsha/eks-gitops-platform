#!/usr/bin/env bash
# Reports ArgoCD sync/health status for every Application and exits non-zero
# if any is out of sync or unhealthy. Needs a live cluster with the `argocd`
# CLI already logged in (`argocd login <server>`) -- see docs/drift-detection.md.
#
# Usage: ./scripts/check-drift.sh [--diff]
#   --diff   also run `argocd app diff <app>` for every app that isn't Synced
set -euo pipefail

show_diff=0
for arg in "$@"; do
  case "$arg" in
    --diff) show_diff=1 ;;
    -h|--help)
      cat <<'EOF'
Usage: ./scripts/check-drift.sh [--diff]

Reports ArgoCD sync/health status for every Application and exits
non-zero if any is out of sync or unhealthy. Needs a live cluster with
the argocd CLI already logged in (argocd login <server>) -- see
docs/drift-detection.md.

  --diff   also run "argocd app diff <app>" for every app that isn't Synced
EOF
      exit 0
      ;;
    *)
      echo "unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

if ! command -v argocd >/dev/null 2>&1; then
  echo "error: argocd CLI not found on PATH (see docs/drift-detection.md)" >&2
  exit 2
fi

apps_json="$(argocd app list -o json)"

drifted=0
echo "App                      Sync          Health"
echo "------------------------ ------------- -------------"
while IFS=$'\t' read -r name sync health; do
  printf '%-25s %-13s %-13s\n' "$name" "$sync" "$health"
  if [ "$sync" != "Synced" ] || [ "$health" != "Healthy" ]; then
    drifted=1
    if [ "$show_diff" -eq 1 ] && [ "$sync" != "Synced" ]; then
      echo "---- argocd app diff $name ----"
      argocd app diff "$name" || true
    fi
  fi
done < <(echo "$apps_json" | ruby -rjson -e '
    JSON.parse(STDIN.read).each do |app|
      name = app.dig("metadata", "name")
      sync = app.dig("status", "sync", "status")
      health = app.dig("status", "health", "status")
      puts [name, sync, health].join("\t")
    end
  ')

if [ "$drifted" -eq 1 ]; then
  echo "drift detected: one or more applications are not Synced/Healthy" >&2
  exit 1
fi

echo "no drift: all applications are Synced and Healthy"
