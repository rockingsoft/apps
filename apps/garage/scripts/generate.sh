#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
ruby scripts/generate-project.rb
