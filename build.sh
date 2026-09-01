#!/bin/bash
# Build NetBar.app with the CommandLineTools toolchain (no Xcode required).
# On a machine with full Xcode, `xcodegen generate` + xcodebuild also works (project.yml).
set -euo pipefail
cd "$(dirname "$0")"

APP=build/NetBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -parse-as-library \
  -target arm64-apple-macos26.0 \
  Sources/*.swift Sources/*/*.swift \
  -o "$APP/Contents/MacOS/NetBar"

cp Info.plist "$APP/Contents/Info.plist"

# Ad-hoc sign (TCC location attribution + SMAppService want a signed bundle).
codesign --force --sign - "$APP"

echo "Built $APP"
