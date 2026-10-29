#!/usr/bin/env bash
set -euo pipefail

mode="${1:?usage: release-version.sh rebuild|major|minor}"
latest_nido="$(git tag --list 'nido-v*' --sort=-version:refname | grep -E '^nido-v[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1 || true)"
latest_legacy="$(git tag --list 'garage-v*' --sort=-version:refname | grep -E '^garage-v[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1 || true)"
latest="${latest_nido:-$latest_legacy}"
if [[ -z "$latest" ]]; then
  current=1.0.0
else
  current="${latest#*-v}"
fi
IFS=. read -r major minor patch <<< "$current"
case "$mode" in
  rebuild) version="$current" ;;
  major) version="$((major + 1)).0.0" ;;
  minor) version="$major.$((minor + 1)).0" ;;
  *) echo "Invalid mode: $mode" >&2; exit 2 ;;
esac
printf 'version=%s\n' "$version"
printf 'previous_tag=%s\n' "$latest_nido"
