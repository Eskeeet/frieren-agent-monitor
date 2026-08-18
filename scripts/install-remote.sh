#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || "$1" == -* ]]; then
  echo "usage: $0 <ssh-target> [display-name]" >&2
  exit 2
fi

target="$1"
name="${2:-$1}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ssh -o BatchMode=yes "$target" 'mkdir -p "$HOME/.frieren-monitor"'
scp "$repo_root/scripts/hook.sh" \
  "$repo_root/scripts/remote-collector.py" \
  "$repo_root/scripts/remote-configure-hooks.py" \
  "$target:.frieren-monitor/"
ssh -o BatchMode=yes "$target" \
  'chmod +x "$HOME/.frieren-monitor/hook.sh" "$HOME/.frieren-monitor/remote-collector.py" && python3 "$HOME/.frieren-monitor/remote-configure-hooks.py"'

/usr/bin/python3 - "$target" "$name" <<'PY'
import json, os, pathlib, sys

target, name = sys.argv[1:]
path = pathlib.Path.home() / ".frieren-monitor" / "hosts.json"
try:
    with open(path, encoding="utf-8") as handle:
        root = json.load(handle)
except (OSError, ValueError):
    root = {"hosts": []}
hosts = root.setdefault("hosts", [])
entry = next((host for host in hosts if host.get("name") == name), None)
if entry is None:
    hosts.append({"name": name, "sshTarget": target})
else:
    entry["sshTarget"] = target
path.parent.mkdir(parents=True, exist_ok=True)
temporary = pathlib.Path(str(path) + ".tmp")
with open(temporary, "w", encoding="utf-8") as handle:
    json.dump(root, handle, indent=2)
    handle.write("\n")
os.replace(temporary, path)
PY

echo "Installed remote monitor on $name ($target)."
