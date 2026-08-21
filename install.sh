#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
destination="${HOME}/Applications/Frieren Monitor.app"

"$repo_root/build.sh"
mkdir -p "${HOME}/Applications"
pkill -x frieren-monitor 2>/dev/null || true
rm -rf "$destination"
ditto "$repo_root/build/Frieren Monitor.app" "$destination"
rm -rf "$repo_root/build"
"$repo_root/scripts/install-hooks.sh"
open "$destination"

echo "Installed: $destination"
