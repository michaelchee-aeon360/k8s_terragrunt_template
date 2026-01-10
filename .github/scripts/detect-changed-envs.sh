#!/bin/bash
set -e

BASE_REF="$1"
K8S_APPS_ROOT="k8s/apps"

git config --global --add safe.directory "$GITHUB_WORKSPACE"
git fetch origin "$BASE_REF":base_branch

CHANGED_FILES=$(git diff --name-only base_branch HEAD)

# Direct env changes
DIRECT_ENV_DIRS=$(echo "$CHANGED_FILES" | \
  grep -E "^$K8S_APPS_ROOT/[^/]+/(dev|staging|prod|dr)/" | \
  sed -E "s|^([^/]+/[^/]+/[^/]+/[^/]+).*|\1|" | sort -u)

# Apps with base/ changes
APPS_WITH_BASE_CHANGED=$(echo "$CHANGED_FILES" | \
  grep -E "^$K8S_APPS_ROOT/[^/]+/base/" | \
  sed -E "s|^$K8S_APPS_ROOT/([^/]+)/base/.*|\1|" | sort -u)

INDIRECT_ENV_DIRS=()
while IFS= read -r app; do
  if [ -n "$app" ]; then
    for env in dev staging prod dr; do
      env_path="$K8S_APPS_ROOT/$app/$env"
      if [ -f "$env_path/kustomization.yaml" ]; then
        INDIRECT_ENV_DIRS+=("$env_path")
      fi
    done
  fi
done <<< "$APPS_WITH_BASE_CHANGED"

ALL_CANDIDATE_DIRS=$(printf '%s\n' "${DIRECT_ENV_DIRS[@]}" "${INDIRECT_ENV_DIRS[@]}" | sort -u)

VALID_DIRS=()
while IFS= read -r dir; do
  if [ -n "$dir" ] && [ -f "$dir/kustomization.yaml" ]; then
    VALID_DIRS+=("$dir")
  fi
done <<< "$ALL_CANDIDATE_DIRS"

if [ ${#VALID_DIRS[@]} -eq 0 ]; then
  echo "no_changes=true" >> "$GITHUB_OUTPUT"
  echo "ℹ️ No relevant environment folders changed (directly or via base)."
else
  echo "no_changes=false" >> "$GITHUB_OUTPUT"
  echo "✅ Will validate these environment(s):"
  printf '  - %s\n' "${VALID_DIRS[@]}"
  echo "changed_dirs<<EOF" >> "$GITHUB_OUTPUT"
  printf '%s\n' "${VALID_DIRS[@]}" >> "$GITHUB_OUTPUT"
  echo "EOF" >> "$GITHUB_OUTPUT"
fi