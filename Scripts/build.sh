#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build dist/k-mac-status.app/Contents/{MacOS,Resources}
SDK="$(xcrun --sdk macosx --show-sdk-path)"
clang -Os -arch arm64 -mmacosx-version-min=26.0 -isysroot "$SDK" -c Sources/Metrics.c -o .build/Metrics.o
swiftc -O -whole-module-optimization -swift-version 5 -target arm64-apple-macosx26.0 -sdk "$SDK" -import-objc-header Sources/Metrics.h Sources/Monitor.swift Sources/Panel.swift Sources/main.swift .build/Metrics.o -framework AppKit -framework IOKit -o dist/k-mac-status.app/Contents/MacOS/k-mac-status
cp Assets/AppIcon.icns Assets/LICENSE-lucide.txt dist/k-mac-status.app/Contents/Resources/
cp Info.plist dist/k-mac-status.app/Contents/Info.plist
codesign --force --sign - dist/k-mac-status.app
printf 'Built: %s/dist/k-mac-status.app\n' "$PWD"
