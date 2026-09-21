#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

xcodebuild -project CalendarWidget.xcodeproj -scheme AgendaMac -configuration Debug \
  -derivedDataPath build/mac CODE_SIGNING_ALLOWED=NO build
xcodebuild -project CalendarWidget.xcodeproj -scheme AgendaiOS -configuration Debug \
  -sdk iphonesimulator -derivedDataPath build/ios CODE_SIGNING_ALLOWED=NO build
