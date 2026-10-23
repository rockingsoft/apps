#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
xcodebuild -project Garage.xcodeproj -scheme Garage -destination 'generic/platform=iOS Simulator' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
