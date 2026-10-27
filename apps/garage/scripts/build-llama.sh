#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ -d build/llama.xcframework ]; then exit 0; fi
mkdir -p build
if ! command -v cmake >/dev/null 2>&1; then
  python3 -m venv build/llama-tools
  build/llama-tools/bin/python -m pip install 'cmake>=3.28,<5'
  PATH="$PWD/build/llama-tools/bin:$PATH"
  export PATH
fi
if [ ! -d build/llama-source/.git ]; then
  git clone --depth 1 --branch b10549 https://github.com/ggml-org/llama.cpp.git build/llama-source
fi
(
  cd build/llama-source
  ./build-xcframework.sh ios-sim ios-device
)
cp -R build/llama-source/build-apple/llama.xcframework build/llama.xcframework
