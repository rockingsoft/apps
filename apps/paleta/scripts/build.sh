#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$root"
swift build -c release
bundle="$root/build/Paleta.app"
version=${PALETA_VERSION:-0.1.0}
build_number=${PALETA_BUILD_NUMBER:-1}
signing_identity=${SIGNING_IDENTITY:--}
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS"
cp "$root/.build/release/Paleta" "$bundle/Contents/MacOS/Paleta"
/usr/bin/plutil -create xml1 "$bundle/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleExecutable -string Paleta "$bundle/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string com.schoren.paleta "$bundle/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleName -string Paleta "$bundle/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleDisplayName -string Paleta "$bundle/Contents/Info.plist"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$bundle/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleShortVersionString -string "$version" "$bundle/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleVersion -string "$build_number" "$bundle/Contents/Info.plist"
/usr/bin/plutil -insert LSMinimumSystemVersion -string 13.0 "$bundle/Contents/Info.plist"
/usr/bin/plutil -insert LSUIElement -bool true "$bundle/Contents/Info.plist"
if [ "$signing_identity" = "-" ]; then
  /usr/bin/codesign --force --sign - "$bundle"
else
  /usr/bin/codesign --force --options runtime --timestamp --sign "$signing_identity" "$bundle"
fi
echo "$bundle"
