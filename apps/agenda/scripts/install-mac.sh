#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
: "${DEVELOPMENT_TEAM:?Indicá DEVELOPMENT_TEAM con tu equipo de Apple Developer}"
app_destination="$HOME/Applications/Agenda.app"
if [ -e "$app_destination" ]; then
  installed_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_destination/Contents/Info.plist")
  [ "$installed_id" = 'com.schoren.calendarwidgetmac' ] || { echo 'El destino pertenece a otra aplicación.' >&2; exit 1; }
fi
xcodebuild -project CalendarWidget.xcodeproj -scheme AgendaMac -configuration Debug \
  -derivedDataPath build/signed-mac DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_IDENTITY='Apple Development' build
python3 scripts/verify-widget-metadata.py build/signed-mac/Build/Products/Debug/AgendaMac.app
mkdir -p "$HOME/Applications"
ditto build/signed-mac/Build/Products/Debug/AgendaMac.app "$app_destination"
codesign --verify --deep --strict "$app_destination"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_destination"
# Avoid registering the build output as a second installed copy.
pluginkit -r "$PWD/build/signed-mac/Build/Products/Debug/AgendaMac.app/Contents/PlugIns/AgendaWidgetMac.appex" || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$PWD/build/signed-mac/Build/Products/Debug/AgendaMac.app"
pluginkit -a "$app_destination/Contents/PlugIns/AgendaWidgetMac.appex"
pluginkit -m -A -D -i com.schoren.calendarwidgetmac.widget
printf '\nInstalada: %s\nAbrí la app y luego Editar widgets → Agenda.\n' "$app_destination"
