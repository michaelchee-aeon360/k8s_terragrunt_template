#!/bin/bash
set -euo pipefail

CHANGED_DIRS="$1"
BASE_BRANCH="$2"

HAS_DIFF=false
while IFS= read -r env_dir; do
  [ -z "$env_dir" ] && continue
  echo "::group::📄 Kustomize diff for $env_dir"

  kubectl kustomize "$env_dir" --enable-helm --load-restrictor LoadRestrictionsNone > /tmp/current.yaml

  git checkout "origin/$BASE_BRANCH" --quiet
  kubectl kustomize "$env_dir" --enable-helm --load-restrictor LoadRestrictionsNone > /tmp/base.yaml
  git checkout - --quiet

  if diff -u /tmp/base.yaml /tmp/current.yaml | sed -E '/^(---|\+\+\+|@@)/d; s/^-/❌ -/; s/^\+/✅ +/'; then
    echo "✅ No diff in $env_dir"
  else
    echo "::warning title=Kustomize Diff::$env_dir has rendered manifest changes"
    HAS_DIFF=true
  fi

  echo "::endgroup::"
done <<< "$CHANGED_DIRS"

if [ "$HAS_DIFF" = true ]; then
  echo "⚠️ One or more environments have rendered manifest changes."
fi