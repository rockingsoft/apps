#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
"$root/scripts/build.sh" >/dev/null
open "$root/build/Paleta.app"
