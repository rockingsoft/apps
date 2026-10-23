#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
xcodebuild -project Garage.xcodeproj -scheme Garage -destination 'generic/platform=iOS Simulator' -derivedDataPath build DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-3SRDN9365G}" CODE_SIGN_STYLE=Automatic build
