#!/usr/bin/env bash
set -euo pipefail

mode="${1:?usage: release-version.sh rebuild|major|minor}"
latest="$(git tag --list 'garage-v*' --sort=-version:refname | grep -E '^garage-v[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1 || true)"
if [[ -z "$latest" ]]; then
  current=1.0.0
else
  current="${latest#garage-v}"
fi
IFS=. read -r major minor patch <<< "$current"
case "$mode" in
  rebuild) version="$current" ;;
  major) version="$((major + 1)).0.0" ;;
  minor) version="$major.$((minor + 1)).0" ;;
  *) echo "Invalid mode: $mode" >&2; exit 2 ;;
esac
printf 'version=%s\n' "$version"
printf 'previous_tag=%s\n' "$latest"
