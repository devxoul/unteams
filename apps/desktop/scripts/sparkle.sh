#!/bin/bash
# Downloads Sparkle into vendor/Sparkle and builds the addon that hosts it, build/sparkle.node.
set -euo pipefail
cd "$(dirname "$0")/.."

SPARKLE_VERSION=2.10.1
if [[ "$(cat vendor/Sparkle/VERSION 2>/dev/null)" != "$SPARKLE_VERSION" ]]; then
  rm -rf vendor/Sparkle
  mkdir -p vendor/Sparkle
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" | tar -xJ -C vendor/Sparkle
  echo "$SPARKLE_VERSION" > vendor/Sparkle/VERSION
fi

mkdir -p build
clang++ native/sparkle.mm -o build/sparkle.node \
  -std=c++17 -fobjc-arc -arch arm64 -arch x86_64 -mmacosx-version-min=12.0 \
  -bundle -undefined dynamic_lookup \
  -I node_modules/node-api-headers/include \
  -F vendor/Sparkle -framework Sparkle -framework Cocoa \
  -Wl,-rpath,@executable_path/../Frameworks
