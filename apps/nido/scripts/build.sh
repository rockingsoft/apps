#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
xcodebuild -project Nido.xcodeproj -scheme Nido -destination 'generic/platform=iOS Simulator' -derivedDataPath build DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-3SRDN9365G}" CODE_SIGN_STYLE=Automatic build
