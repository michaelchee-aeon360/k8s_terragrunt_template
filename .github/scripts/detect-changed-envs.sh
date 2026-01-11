#!/bin/bash
set -e

BASE_REF="$1"
K8S_APPS_ROOT="k8s/apps"
HELM_CHARTS_ROOT="k8s/helm-charts"

git config --global --add safe.directory "$GITHUB_WORKSPACE"
git fetch origin "$BASE_REF":base_branch

CHANGED_FILES=$(git diff --name-only base_branch HEAD)

# --- 1. Apps with direct changes ---
DIRECT_APPS=$(echo "$CHANGED_FILES" | \
  grep -E "^$K8S_APPS_ROOT/[^/]+/" | \
  sed -E "s|^$K8S_APPS_ROOT/([^/]+)/.*|\1|" | sort -u)

# --- 2. Apps affected by Helm chart changes ---
HELM_AFFECTED_APPS=()

if echo "$CHANGED_FILES" | grep -q "^$HELM_CHARTS_ROOT/"; then
  # Extract changed Helm chart names
  CHANGED_HELM_CHARTS=$(echo "$CHANGED_FILES" | \
    grep -E "^$HELM_CHARTS_ROOT/[^/]+/" | \
    sed -E "s|^$HELM_CHARTS_ROOT/([^/]+)/.*|\1|" | sort -u)

  echo "🔍 Detected changes in Helm charts: $(echo $CHANGED_HELM_CHARTS)"

  # Scan every app directory
  while IFS= read -r -d '' app_dir; do
    app_name=$(basename "$app_dir")
    echo "🔍 Scanning app: $app_name"

    for layer in base dev staging prod dr; do
      kust_file="$app_dir/$layer/kustomization.yaml"
      if [ ! -f "$kust_file" ]; then
        continue
      fi

      echo "  -> Checking: $kust_file"
      chart_names_raw=$(yq eval '.helmCharts[].name // []' "$kust_file" 2>/dev/null || true)
      if [ -n "$chart_names_raw" ]; then
        while IFS= read -r chart; do
            # Trim whitespace
            chart=$(echo "$chart" | xargs)
            if [ -n "$chart" ] && echo "$CHANGED_HELM_CHARTS" | grep -Fxq "$chart"; then
            echo "     ✅ Match found: '$chart' → marking app '$app_name'"
            HELM_AFFECTED_APPS+=("$app_name")
            break 2
            fi
        done <<< "$chart_names_raw"
      fi
    done
  done < <(find "$K8S_APPS_ROOT" -mindepth 1 -maxdepth 1 -type d -print0)
fi

echo "helm app: $HELM_AFFECTED_APPS"


# --- Combine and deduplicate ---
ALL_APPS=$(printf '%s\n' "${DIRECT_APPS[@]}" "${HELM_AFFECTED_APPS[@]}" | sort -u)

VALID_DIRS=()

if [ -z "$ALL_APPS" ]; then
  echo "no_changes=true" >> "$GITHUB_OUTPUT"
  echo "ℹ️ No relevant changes detected."
else
  echo "✅ Apps to validate:"
  while IFS= read -r app; do
    [ -z "$app" ] && continue
    echo "  - $app"
    for env in dev staging prod dr; do
      env_dir="$K8S_APPS_ROOT/$app/$env"
      if [ -f "$env_dir/kustomization.yaml" ]; then
        VALID_DIRS+=("$env_dir")
      fi
    done
  done <<< "$ALL_APPS"

  if [ ${#VALID_DIRS[@]} -eq 0 ]; then
    echo "no_changes=true" >> "$GITHUB_OUTPUT"
    echo "⚠️ Apps identified, but no valid environments found."
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