#!/bin/bash
set -e

K8S_APPS_ROOT="k8s/apps"

# 1. YAML Formatting Check
echo "🔍 Checking YAML formatting..."
formatted_files=()
while IFS= read -r -d '' file; do
  if ! yq eval '.' "$file" > /tmp/formatted.yaml 2>/dev/null; then
    echo "❌ Invalid YAML syntax in $file"
    exit 1
  fi
  if ! cmp -s "$file" /tmp/formatted.yaml; then
    formatted_files+=("$file")
  fi
done < <(find . -path "./$K8S_APPS_ROOT/*/*/*.yaml" -print0 2>/dev/null || true)

if [ ${#formatted_files[@]} -gt 0 ]; then
  echo "❌ The following files need reformatting:"
  printf '  %s\n' "${formatted_files[@]}"
  echo ""
  echo "💡 Fix with: yq eval '.' -i <file>"
  exit 1
else
  echo "✅ All YAML files are correctly formatted."
fi

# 2. App Name Validation
echo "🔍 Validating app name format..."
while IFS= read -r -d '' app_dir; do
  app_name=$(basename "$app_dir")
  if [[ ! "$app_name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    echo "❌ Invalid app name: '$app_name'"
    echo "   → Must contain only lowercase letters, digits, and dashes (e.g., my-app-v1)."
    exit 1
  fi
done < <(find "./$K8S_APPS_ROOT" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null || true)

echo "✅ All app names are valid."