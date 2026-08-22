#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app="$repo_root/build/Frieren Monitor.app"
contents="$app/Contents"

rm -rf "$repo_root/build"
mkdir -p "$contents/MacOS" "$contents/Resources"

if [[ -z "${SDKROOT:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]]; then
  export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
fi
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/frieren-monitor-clang-cache}"
export SWIFT_MODULE_CACHE_PATH="${SWIFT_MODULE_CACHE_PATH:-/tmp/frieren-monitor-swift-cache}"

swiftc "$repo_root"/Sources/FrierenMonitor/*.swift \
  -o "$contents/MacOS/frieren-monitor" \
  -target "$(uname -m)-apple-macos13.0" \
  -framework Foundation -framework AppKit -framework SwiftUI

cp "$repo_root/Resources/Info.plist" "$contents/Info.plist"
find "$repo_root/Resources" -maxdepth 1 -type f \
  \( -name '*-spritesheet.png' -o -name '*.icns' \) \
  -exec cp {} "$contents/Resources/" \;
cp "$repo_root/scripts/hook.sh" \
  "$repo_root/scripts/remote-collector.py" \
  "$repo_root/scripts/remote-configure-hooks.py" \
  "$contents/Resources/"
chmod +x "$contents/Resources/hook.sh"
codesign --force --deep --sign - "$app"
echo "Built: $app"
