#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
xcrun swiftc Shared/Agenda.swift Tests/AgendaDatesTests.swift -o .build/agenda-tests
.build/agenda-tests
