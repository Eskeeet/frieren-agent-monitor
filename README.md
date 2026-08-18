# Frieren Agent Monitor

A local, open-source macOS desktop companion for Claude Code, Codex, and Cursor.
Frieren floats above the desktop without a dashboard frame and keeps an eye on
local agent sessions.

<p align="center">
  <img src="Resources/frieren-spritesheet.png" alt="Frieren Agent Monitor animation sprites" width="420">
</p>

## Behavior

- Sleeping: no active sessions
- Walking: one or more sessions are running
- Orange alert: a session needs input
- Waving with a green halo: a session just finished
- Hover: reveal running, waiting, and recently finished sessions
- Click Frieren: play an interaction animation
- Drag Frieren: move her around the desktop
- Click an active session: focus its app or open its project

Waiting and completion events also appear briefly in a notification bubble. All
process and session data stays on the Mac.

## Requirements

- macOS 13 or later
- Swift 5.9 or later (Xcode or the Xcode Command Line Tools)

## Build and run

Build and launch from the repository:

```bash
./build.sh
open -n "build/Frieren Monitor.app"
```

To improve state detection, install hooks for any supported agents already
configured on this Mac:

```bash
./scripts/install-hooks.sh
```

Alternatively, build the app, install it in `~/Applications`, configure the
hooks, and launch it in one step:

```bash
./install.sh
```

Frieren discovers Claude Code and Cursor from local process and session data,
and Codex from top-level rollout logs. Internal Codex subagent turns are folded
into their parent task, while Cursor lifecycle hooks remain authoritative across
restarts of its persistent Agents Window host. Cursor rows use a short version
of the latest submitted prompt as their session summary. The hook installer
copies its event script to `~/.frieren-monitor/hook.sh` and adds entries alongside
existing hooks in:

- `~/.claude/settings.json`
- `~/.codex/hooks.json`
- `~/.cursor/hooks.json`

Only configuration directories that already exist are updated. Restart active
agent sessions after installing hooks.

## License

[MIT](LICENSE)
