#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
"$root/scripts/build.sh" >/dev/null
destination="$HOME/Applications/Paleta.app"
mkdir -p "$HOME/Applications"
/usr/bin/ditto "$root/build/Paleta.app" "$destination"
echo "Instalada en $destination"
