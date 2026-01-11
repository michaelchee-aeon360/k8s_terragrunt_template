#!/bin/bash
set -e

BASE_REF="$1"
K8S_APPS_ROOT="k8s/apps"
HELM_CHARTS_ROOT="k8s/helm-charts"
ENV_LAYERS=("base" "dev" "staging" "prod" "dr")

git config --global --add safe.directory "$GITHUB_WORKSPACE"
git fetch origin "$BASE_REF":base_branch

CHANGED_FILES=$(git diff --name-only base_branch HEAD)

# --- 1. Direct changes to non-base env dirs ---
DIRECT_ENV_DIRS=$(echo "$CHANGED_FILES" | \
  grep -E "^$K8S_APPS_ROOT/[^/]+/(dev|staging|prod|dr)/" | \
  sed -E "s|^([^/]+/[^/]+/[^/]+/[^/]+).*|\1|" | sort -u)

# --- 2. Apps with base/ changes ---
APPS_WITH_BASE_CHANGED=$(echo "$CHANGED_FILES" | \
  grep -E "^$K8S_APPS_ROOT/[^/]+/base/" | \
  sed -E "s|^$K8S_APPS_ROOT/([^/]+)/base/.*|\1|" | sort -u)

# --- 3. Helm chart changes ---
CHANGED_HELM_CHARTS=$(echo "$CHANGED_FILES" | \
  grep -E "^$HELM_CHARTS_ROOT/[^/]+/" | \
  sed -E "s|^$HELM_CHARTS_ROOT/([^/]+)/.*|\1|" | sort -u)

APPS_AFFECTED_BY_HELM=()

if [ -n "$CHANGED_HELM_CHARTS" ]; then
  echo "🔍 Detected changes in Helm charts: $(echo $CHANGED_HELM_CHARTS)"
  
  while IFS= read -r app_dir; do
    app_name=$(basename "$app_dir")
    marked=false

    for layer in "${ENV_LAYERS[@]}"; do
      kust_file="$app_dir/$layer/kustomization.yaml"
      [ ! -f "$kust_file" ] && continue

      # Check for exact chartHome path used for local charts
      chart_home=$(yq eval '.helmGlobals.chartHome // empty' "$kust_file" 2>/dev/null || true)
      if [ "$chart_home" != "../../../helm-charts" ]; then
        continue
      fi

      # Extract Helm chart names
      chart_names_raw=$(yq eval '.helmCharts[].name // []' "$kust_file" 2>/dev/null || true)
      [ -z "$chart_names_raw" ] && continue

      # Check each chart name
      while IFS= read -r chart; do
        chart=$(echo "$chart" | xargs)
        if [ -n "$chart" ] && echo "$CHANGED_HELM_CHARTS" | grep -Fxq "$chart"; then
          APPS_AFFECTED_BY_HELM+=("$app_name")
          marked=true
          break 2  # break layer loop and chart loop
        fi
      done <<< "$(echo "$chart_names_raw" | yq eval -o=j -I=0 '.[]' - | tr -d '"')"
    done
  done < <(find "$K8S_APPS_ROOT" -mindepth 1 -maxdepth 1 -type d -print0 | xargs -0)
fi

# --- Collect all environment dirs to validate ---
ALL_DIRS=()

# Helper: add all valid (non-base) envs for an app
add_envs_for_app() {
  local app="$1"
  for env in dev staging prod dr; do
    dir="$K8S_APPS_ROOT/$app/$env"
    if [ -f "$dir/kustomization.yaml" ]; then
      ALL_DIRS+=("$dir")
    fi
  done
}

# From direct changes
while IFS= read -r dir; do
  [ -n "$dir" ] && ALL_DIRS+=("$dir")
done <<< "$DIRECT_ENV_DIRS"

# From base/ changes
while IFS= read -r app; do
  [ -n "$app" ] && add_envs_for_app "$app"
done <<< "$APPS_WITH_BASE_CHANGED"

# From Helm chart usage
for app in "${APPS_AFFECTED_BY_HELM[@]}"; do
  add_envs_for_app "$app"
done

# Deduplicate
VALID_DIRS=($(printf '%s\n' "${ALL_DIRS[@]}" | sort -u))

# --- Output to GitHub Actions ---
if [ ${#VALID_DIRS[@]} -eq 0 ]; then
  echo "no_changes=true" >> "$GITHUB_OUTPUT"
  echo "ℹ️ No relevant environment folders changed."
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