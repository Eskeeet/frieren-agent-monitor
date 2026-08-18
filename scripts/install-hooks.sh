#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
state_dir="${HOME}/.frieren-monitor"
hook_path="${state_dir}/hook.sh"
mkdir -p "$state_dir"
cp "$repo_root/scripts/hook.sh" "$hook_path"
chmod +x "$hook_path"

/usr/bin/python3 - "$hook_path" <<'PY'
import json, os, pathlib, sys

hook = sys.argv[1]

def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}

def write(path, root):
    pathlib.Path(path).parent.mkdir(parents=True, exist_ok=True)
    tmp = path + ".frieren-monitor.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(root, f, indent=2, sort_keys=True)
        f.write("\n")
    os.replace(tmp, path)

def matcher_hooks(path, agent):
    root = read(path)
    hooks = root.setdefault("hooks", {})
    for event, arg, timeout in (("Stop", "stop", 30), ("PermissionRequest", "permission", 600)):
        groups = hooks.setdefault(event, [])
        command = f"{hook} {agent} {arg}"
        exists = any(item.get("command") == command for group in groups for item in group.get("hooks", []))
        if not exists:
            groups.append({"matcher": "", "hooks": [{"type": "command", "command": command, "timeout": timeout}]})
    write(path, root)

def cursor_hooks(path):
    root = read(path)
    hooks = root.setdefault("hooks", {})
    stops = hooks.setdefault("stop", [])
    command = f"{hook} cursor stop"
    if not any(item.get("command") == command for item in stops):
        stops.append({"type": "command", "command": command})
    write(path, root)

home = os.path.expanduser("~")
targets = [
    (os.path.join(home, ".claude", "settings.json"), lambda p: matcher_hooks(p, "claude-code")),
    (os.path.join(home, ".codex", "hooks.json"), lambda p: matcher_hooks(p, "codex")),
    (os.path.join(home, ".cursor", "hooks.json"), cursor_hooks),
]

for path, configure in targets:
    if os.path.isdir(os.path.dirname(path)):
        configure(path)
        print(f"wired {path}")
PY

echo "Frieren Monitor hooks installed alongside existing hooks."
