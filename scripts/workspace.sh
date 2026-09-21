#!/bin/sh
set -eu

workspace_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
apps_root="$workspace_root/apps"

usage() {
  cat <<'EOF'
Uso:
  ./scripts/workspace.sh list
  ./scripts/workspace.sh check
  ./scripts/workspace.sh <test|build|open|generate|install-mac> <app>
  ./scripts/workspace.sh all <test|build|generate>
  ./scripts/workspace.sh new <app-id> <nombre visible>
EOF
}

app_dir() {
  app_id=$1
  case "$app_id" in
    ''|*[!a-z0-9-]*) echo "ID de app inválido: $app_id" >&2; exit 2 ;;
  esac
  candidate="$apps_root/$app_id"
  [ -f "$candidate/app.json" ] || { echo "App desconocida: $app_id" >&2; exit 2; }
  printf '%s\n' "$candidate"
}

list_apps() {
  found=false
  for manifest in "$apps_root"/*/app.json; do
    [ -f "$manifest" ] || continue
    found=true
    app_id=$(/usr/bin/plutil -extract id raw "$manifest")
    app_name=$(/usr/bin/plutil -extract name raw "$manifest")
    app_description=$(/usr/bin/plutil -extract description raw "$manifest" 2>/dev/null || true)
    printf '%s\t%s\t%s\n' "$app_id" "$app_name" "$app_description"
  done
  $found || echo 'No hay apps.'
}

check_apps() {
  status=0
  for manifest in "$apps_root"/*/app.json; do
    [ -f "$manifest" ] || continue
    directory=$(dirname "$manifest")
    folder_id=$(basename "$directory")
    if ! manifest_id=$(/usr/bin/plutil -extract id raw "$manifest" 2>/dev/null); then
      echo "ERROR: manifiesto inválido o sin id: $manifest" >&2
      status=1
      continue
    fi
    if ! /usr/bin/plutil -extract name raw "$manifest" >/dev/null 2>&1; then
      echo "ERROR: manifiesto sin nombre: $manifest" >&2
      status=1
      continue
    fi
    if [ "$folder_id" != "$manifest_id" ]; then
      echo "ERROR: $manifest declara id=$manifest_id" >&2
      status=1
    elif [ ! -f "$directory/README.md" ]; then
      echo "ERROR: falta $directory/README.md" >&2
      status=1
    else
      echo "OK: $folder_id"
    fi
  done
  return "$status"
}

run_app_command() {
  command_name=$1
  directory=$(app_dir "$2")
  script="$directory/scripts/$command_name.sh"
  [ -x "$script" ] || { echo "La app $2 no implementa '$command_name'." >&2; exit 2; }
  exec "$script"
}

run_all() {
  command_name=$1
  case "$command_name" in test|build|generate) ;; *) echo "Comando no permitido con all: $command_name" >&2; exit 2 ;; esac
  ran=false
  for manifest in "$apps_root"/*/app.json; do
    [ -f "$manifest" ] || continue
    directory=$(dirname "$manifest")
    script="$directory/scripts/$command_name.sh"
    [ -x "$script" ] || continue
    ran=true
    echo "==> $(basename "$directory"): $command_name"
    "$script"
  done
  $ran || echo "Ninguna app implementa '$command_name'."
}

new_app() {
  app_id=$1
  display_name=$2
  case "$app_id" in ''|*[!a-z0-9-]*) echo 'El ID debe usar minúsculas, números y guiones.' >&2; exit 2 ;; esac
  destination="$apps_root/$app_id"
  [ ! -e "$destination" ] || { echo "Ya existe: $destination" >&2; exit 2; }
  mkdir -p "$destination/scripts" "$destination/Sources" "$destination/Tests"
  APP_ID="$app_id" DISPLAY_NAME="$display_name" /usr/bin/python3 -c '
import json
import os
import sys

manifest = {
    "id": os.environ["APP_ID"],
    "name": os.environ["DISPLAY_NAME"],
    "description": "",
    "platforms": [],
}
with open(sys.argv[1], "w", encoding="utf-8") as output:
    json.dump(manifest, output, ensure_ascii=False, indent=2)
    output.write("\n")
' "$destination/app.json"
  printf '# %s\n\nDescribir aquí el propósito, las plataformas y cómo ejecutar esta app.\n' "$display_name" > "$destination/README.md"
  touch "$destination/Sources/.gitkeep" "$destination/Tests/.gitkeep" "$destination/scripts/.gitkeep"
  echo "Creada: apps/$app_id"
}

command_name=${1:-}
case "$command_name" in
  list) [ "$#" -eq 1 ] || { usage >&2; exit 2; }; list_apps ;;
  check) [ "$#" -eq 1 ] || { usage >&2; exit 2; }; check_apps ;;
  test|build|open|generate|install-mac) [ "$#" -eq 2 ] || { usage >&2; exit 2; }; run_app_command "$1" "$2" ;;
  all) [ "$#" -eq 2 ] || { usage >&2; exit 2; }; run_all "$2" ;;
  new) [ "$#" -eq 3 ] || { usage >&2; exit 2; }; new_app "$2" "$3" ;;
  *) usage >&2; exit 2 ;;
esac
