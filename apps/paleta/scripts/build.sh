#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$root"
swift build -c release
bundle="$root/build/Paleta.app"
mkdir -p "$bundle/Contents/MacOS"
cp "$root/.build/release/Paleta" "$bundle/Contents/MacOS/Paleta"
/usr/bin/plutil -create xml1 "$bundle/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleExecutable -string Paleta "$bundle/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string com.schoren.paleta "$bundle/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleName -string Paleta "$bundle/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleDisplayName -string Paleta "$bundle/Contents/Info.plist"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$bundle/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleShortVersionString -string 0.1.0 "$bundle/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleVersion -string 1 "$bundle/Contents/Info.plist"
/usr/bin/plutil -insert LSMinimumSystemVersion -string 13.0 "$bundle/Contents/Info.plist"
/usr/bin/plutil -insert LSUIElement -bool true "$bundle/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$bundle"
echo "$bundle"
