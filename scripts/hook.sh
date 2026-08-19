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
import hashlib, json, sys, time
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

request_key = None
if event in {"permission", "resume"}:
    identity = [payload.get("agent_id"), payload.get("tool_name"), payload.get("tool_input")]
    encoded = json.dumps(identity, sort_keys=True, separators=(",", ":")).encode()
    request_key = hashlib.sha256(encoded).hexdigest()

with open(path, "a", encoding="utf-8") as handle:
    handle.write(json.dumps({
        "timestamp": time.time(), "agent": agent, "event": event,
        "projectPath": project, "pid": int(pid), "title": title,
        "requestKey": request_key,
    }, separators=(",", ":")) + "\n")
' "$state_dir/events.jsonl" "$agent" "$event" "$project_path" "$pid_value" <<<"$payload"
