#!/usr/bin/env bash
set -euo pipefail

agent="${1:-agent}"
event="${2:-stop}"
if [[ ! -t 0 ]]; then payload="$(cat)"; else payload=""; fi

state_dir="${HOME}/.frieren-monitor"
mkdir -p "$state_dir"
project_path="${PWD}"
pid_value="${PPID}"

/usr/bin/python3 - "$state_dir/events.jsonl" "$agent" "$event" "$project_path" "$pid_value" <<'PY'
import json, sys, time
path, agent, event, project, pid = sys.argv[1:]
with open(path, "a", encoding="utf-8") as handle:
    handle.write(json.dumps({
        "timestamp": time.time(), "agent": agent, "event": event,
        "projectPath": project, "pid": int(pid),
    }, separators=(",", ":")) + "\n")
PY
