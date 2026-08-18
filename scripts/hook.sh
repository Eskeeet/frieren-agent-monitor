#!/usr/bin/env bash
set -euo pipefail

agent="${1:-agent}"
event="${2:-stop}"
if [[ ! -t 0 ]]; then payload="$(cat)"; else payload=""; fi

state_dir="${HOME}/.frieren-monitor"
mkdir -p "$state_dir"
project_path="${PWD}"
pid_value="${PPID}"

/usr/bin/python3 -c '
import json, sys, time
path, agent, event, project, pid = sys.argv[1:]

try:
    payload = json.load(sys.stdin)
except (json.JSONDecodeError, UnicodeDecodeError):
    payload = {}

if agent == "cursor":
    roots = payload.get("workspace_roots")
    if isinstance(roots, list) and roots and isinstance(roots[0], str):
        project = roots[0]
    elif project.rstrip("/").endswith("/.cursor"):
        project = None

title = payload.get("prompt") if event == "start" else None
if isinstance(title, str):
    title = " ".join(title.split())
    if len(title) > 100:
        title = title[:99].rstrip() + "…"
else:
    title = None

with open(path, "a", encoding="utf-8") as handle:
    handle.write(json.dumps({
        "timestamp": time.time(), "agent": agent, "event": event,
        "projectPath": project, "pid": int(pid), "title": title,
    }, separators=(",", ":")) + "\n")
' "$state_dir/events.jsonl" "$agent" "$event" "$project_path" "$pid_value" <<<"$payload"
