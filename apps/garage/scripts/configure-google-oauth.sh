#!/bin/sh
set -eu
if [ "$#" -ne 1 ]; then
  echo "Uso: $0 <ID del cliente OAuth de iOS>" >&2
  exit 2
fi
client_id=$1
case "$client_id" in
  *.apps.googleusercontent.com) ;;
  *) echo "El ID debe terminar en .apps.googleusercontent.com" >&2; exit 2 ;;
esac
redirect_scheme=$(printf '%s' "$client_id" | awk -F. '{ for (i=NF; i>=1; i--) { printf "%s%s", $i, (i>1 ? "." : "") } }')
directory=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cat > "$directory/App/GoogleConfig.xcconfig" <<EOF
// Cliente OAuth de tipo iOS para com.schoren.garage. Los IDs de cliente no son secretos.
GARAGE_GOOGLE_CLIENT_ID = $client_id
GARAGE_GOOGLE_REDIRECT_SCHEME = $redirect_scheme
EOF
echo "Google OAuth configurado para Garage. Reconstruí la app antes de probar el inicio de sesión."
