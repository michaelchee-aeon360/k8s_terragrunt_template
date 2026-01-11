#!/bin/bash
set -e

BASE_REF="$1"
K8S_APPS_ROOT="k8s/apps"

git config --global --add safe.directory "$GITHUB_WORKSPACE"
git fetch origin "$BASE_REF":base_branch

CHANGED_FILES=$(git diff --name-only base_branch HEAD)

CHANGED_APPS=$(echo "$CHANGED_FILES" | \
  grep -E "^$K8S_APPS_ROOT/[^/]+/" | \
  sed -E "s|^$K8S_APPS_ROOT/([^/]+)/.*|\1|" | \
  sort -u)

VALID_DIRS=()

if [ -z "$CHANGED_APPS" ]; then
  echo "no_changes=true" >> "$GITHUB_OUTPUT"
  echo "ℹ️ No changes detected in k8s/apps/."
else
  echo "✅ Apps with changes:"
  while IFS= read -r app; do
    [ -z "$app" ] && continue
    echo "  - $app"
    for env in dev staging prod dr; do
      env_dir="$K8S_APPS_ROOT/$app/$env"
      if [ -f "$env_dir/kustomization.yaml" ]; then
        VALID_DIRS+=("$env_dir")
      fi
    done
  done <<< "$CHANGED_APPS"  # ← HERE: no pipe, uses here-string

  if [ ${#VALID_DIRS[@]} -eq 0 ]; then
    echo "no_changes=true" >> "$GITHUB_OUTPUT"
    echo "⚠️ Apps changed, but no valid environments found (missing kustomization.yaml)."
  else
    echo "no_changes=false" >> "$GITHUB_OUTPUT"
    echo "✅ Will validate these environment(s):"
    printf '  - %s\n' "${VALID_DIRS[@]}"
    {
      echo "changed_dirs<<EOF"
      printf '%s\n' "${VALID_DIRS[@]}"
      echo "EOF"
    } >> "$GITHUB_OUTPUT"
  fi
fi