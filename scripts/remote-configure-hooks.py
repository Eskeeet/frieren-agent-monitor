#!/usr/bin/env python3
"""Install Frieren lifecycle hooks without replacing existing hooks."""

import json
import os
import pathlib

HOME = pathlib.Path.home()
HOOK = HOME / ".frieren-monitor" / "hook.sh"


def read(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return {}


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = pathlib.Path(str(path) + ".frieren-monitor.tmp")
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.replace(temporary, path)


def matcher_hooks(path, agent):
    root = read(path)
    hooks = root.setdefault("hooks", {})
    for event, argument, timeout in (("Stop", "stop", 30), ("PermissionRequest", "permission", 600)):
        groups = hooks.setdefault(event, [])
        command = f"{HOOK} {agent} {argument}"
        if not any(item.get("command") == command for group in groups for item in group.get("hooks", [])):
            groups.append({"matcher": "", "hooks": [{"type": "command", "command": command, "timeout": timeout}]})
    write(path, root)


def cursor_hooks(path):
    root = read(path)
    root["version"] = 1
    hooks = root.setdefault("hooks", {})
    for event, argument in (("beforeSubmitPrompt", "start"), ("stop", "stop")):
        entries = hooks.setdefault(event, [])
        command = f"{HOOK} cursor {argument}"
        if not any(item.get("command") == command for item in entries):
            entries.append({"type": "command", "command": command})
    write(path, root)


targets = (
    (HOME / ".claude" / "settings.json", lambda path: matcher_hooks(path, "claude-code")),
    (HOME / ".codex" / "hooks.json", lambda path: matcher_hooks(path, "codex")),
    (HOME / ".cursor" / "hooks.json", cursor_hooks),
)
for path, configure in targets:
    if path.parent.is_dir():
        configure(path)
        print(f"wired {path}")
