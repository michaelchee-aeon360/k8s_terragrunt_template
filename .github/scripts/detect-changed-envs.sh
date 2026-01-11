#!/bin/bash
set -e

BASE_REF="$1"
K8S_APPS_ROOT="k8s/apps"
HELM_CHARTS_ROOT="k8s/helm-charts"
ENV_DIRS=("base" "dev" "staging" "prod" "dr")

git config --global --add safe.directory "$GITHUB_WORKSPACE"
git fetch origin "$BASE_REF":base_branch

CHANGED_FILES=$(git diff --name-only base_branch HEAD)

# --- 1. Direct env changes (non-base) ---
DIRECT_ENV_DIRS=$(echo "$CHANGED_FILES" | \
  grep -E "^$K8S_APPS_ROOT/[^/]+/(dev|staging|prod|dr)/" | \
  sed -E "s|^([^/]+/[^/]+/[^/]+/[^/]+).*|\1|" | sort -u)

# --- 2. Apps whose base/ changed ---
APPS_WITH_BASE_CHANGED=$(echo "$CHANGED_FILES" | \
  grep -E "^$K8S_APPS_ROOT/[^/]+/base/" | \
  sed -E "s|^$K8S_APPS_ROOT/([^/]+)/base/.*|\1|" | sort -u)

# --- 3. Detect changed Helm charts ---
CHANGED_HELM_CHARTS=$(echo "$CHANGED_FILES" | \
  grep -E "^$HELM_CHARTS_ROOT/[^/]+/" | \
  sed -E "s|^$HELM_CHARTS_ROOT/([^/]+)/.*|\1|" | sort -u)

APPS_AFFECTED_BY_HELM=()

if [ -n "$CHANGED_HELM_CHARTS" ]; then
  echo "🔍 Detected changes in Helm charts: $(echo $CHANGED_HELM_CHARTS)"
  
  while IFS= read -r app_dir; do
    app_name=$(basename "$app_dir")
    app_marked=false

    # Check base + all overlays
    for layer in "${ENV_DIRS[@]}"; do
      kust_file="$app_dir/$layer/kustomization.yaml"
      if [ ! -f "$kust_file" ]; then
        continue
      fi

      # Extract chartHome
      chart_home=$(yq eval '.helmGlobals.chartHome // empty' "$kust_file" 2>/dev/null || true)
      if [ -z "$chart_home" ]; then
        continue
      fi

      # Resolve chartHome relative to kustomization.yaml
      kust_dir="$(dirname "$kust_file")"
      resolved=""
      if [ "${chart_home#/}" = "$chart_home" ]; then
        # Relative path
        resolved="$(cd "$kust_dir" && realpath -m "$chart_home" 2>/dev/null || echo "$kust_dir/$chart_home")"
      else
        resolved="$chart_home"
      fi

      # Normalize both paths for comparison
      expected_abs="$GITHUB_WORKSPACE/$HELM_CHARTS_ROOT"
      actual_abs="$GITHUB_WORKSPACE/$resolved"

      normalized_expected=$(realpath -m "$expected_abs" 2>/dev/null || echo "$expected_abs")
      normalized_actual=$(realpath -m "$actual_abs" 2>/dev/null || echo "$actual_abs")

      if [ "$normalized_actual" != "$normalized_expected" ]; then
        continue
      fi

      # Now check if any referenced chart was changed
      chart_names_raw=$(yq eval '.helmCharts[].name // []' "$kust_file" 2>/dev/null || true)
      if [ -z "$chart_names_raw" ]; then
        continue
      fi

      while IFS= read -r chart; do
        chart=$(echo "$chart" | xargs)
        if [ -n "$chart" ] && echo "$CHANGED_HELM_CHARTS" | grep -Fxq "$chart"; then
          APPS_AFFECTED_BY_HELM+=("$app_name")
          app_marked=true
          break 2  # break out of both inner loop and layer loop
        fi
      done <<< "$(echo "$chart_names_raw" | yq eval -o=j -I=0 '.[]' - | tr -d '"')"
    done
  done < <(find "$K8S_APPS_ROOT" -mindepth 1 -maxdepth 1 -type d -print0 | xargs -0)
fi

# --- Build full list of env dirs to validate ---
ALL_ENV_DIRS_TO_VALIDATE=()

add_all_valid_envs_for_app() {
  local app="$1"
  for env in dev staging prod dr; do
    env_path="$K8S_APPS_ROOT/$app/$env"
    if [ -f "$env_path/kustomization.yaml" ]; then
      ALL_ENV_DIRS_TO_VALIDATE+=("$env_path")
    fi
  done
}

# From direct changes
while IFS= read -r dir; do
  [ -n "$dir" ] && ALL_ENV_DIRS_TO_VALIDATE+=("$dir")
done <<< "$DIRECT_ENV_DIRS"

# From base/ changes
while IFS= read -r app; do
  [ -n "$app" ] && add_all_valid_envs_for_app "$app"
done <<< "$APPS_WITH_BASE_CHANGED"

# From Helm chart usage (any layer)
for app in "${APPS_AFFECTED_BY_HELM[@]}"; do
  add_all_valid_envs_for_app "$app"
done

# Deduplicate
VALID_DIRS=($(printf '%s\n' "${ALL_ENV_DIRS_TO_VALIDATE[@]}" | sort -u))

# --- Output ---
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