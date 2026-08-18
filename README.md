# Frieren Monitor

A local, open-source desktop companion for Claude Code, Codex, and Cursor.
Frieren stays on the desktop without a dashboard frame. Hover over her to see
running, waiting, and recently finished sessions.

## Behavior

- sleeping: no active sessions
- walking: one or more sessions are running
- orange alert: a session needs input
- waving with a green halo: a session just finished
- hover: reveal the local session list and controls

All process and session data stays on the Mac.

## Build and run

```bash
./build.sh
open -n "build/Frieren Monitor.app"
./scripts/install-hooks.sh
```

Or install the app into `~/Applications`, wire the hooks, and launch it:

```bash
./install.sh
```

The app reads native Claude Code sidecars and scans local Claude Code, Codex,
and Cursor Agent processes. `scripts/install-hooks.sh` adds the event endpoint
alongside existing hooks for exact stop and permission signals. Restart active
agent sessions after installing hooks.
