# Frieren Agent Monitor

A local, open-source macOS desktop companion for Claude Code, Codex, and Cursor.
Frieren floats above the desktop without a dashboard frame and keeps an eye on
agent sessions running locally or on remote machines reached through SSH.

<p align="center">
  <img src="Resources/frieren-spritesheet.png" alt="Frieren Agent Monitor animation sprites" width="420">
</p>

## Behavior

- Sleeping: no active sessions
- Walking: one or more sessions are running
- Orange alert: a session needs input
- Waving with a green halo: a session just finished
- Idle: a live agent process is open but is not waiting for user input
- Hover: reveal running, waiting, and recently finished sessions
- Click Frieren: play an interaction animation
- Drag Frieren: move her around the desktop
- Right-click Frieren: set up monitoring for a remote SSH machine
- Click an active session: focus its app or open its project
- Click a remote session: open an SSH connection in the system terminal

Waiting and completion events also appear briefly in a notification bubble.
Session data stays on the Mac and explicitly configured SSH hosts; Frieren does
not send it to an external service.

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

## Remote machines over SSH

Remote monitoring uses the system OpenSSH client, including aliases, proxy
jumps, keys, and host-key policy from `~/.ssh/config`. Password prompts are not
supported; verify that `ssh <target>` works with key-based authentication first.

Right-click Frieren and choose **Set Up Remote SSH…**. Enter an SSH target or
alias, an optional display name, and an optional identity file, then click
**Set Up**. Frieren installs the read-only collector and lifecycle hooks and
registers the machine automatically.

SSH must already work with a key or `ssh-agent`; interactive password prompts
are not supported. New host keys are accepted on first connection, while
changed host keys are rejected.

For command-line setup, run:

```bash
./scripts/install-remote.sh dev-vm "Development VM"
```

The first argument is an SSH target or `~/.ssh/config` alias. The optional
second argument is the name shown by Frieren. The installer adds the host to
`~/.frieren-monitor/hosts.json`. It preserves existing agent hooks.

Hosts can also be configured manually:

```json
{
  "hosts": [
    {
      "name": "Development VM",
      "sshTarget": "dev-vm",
      "identityFile": "~/.ssh/id_ed25519",
      "enabled": true
    }
  ]
}
```

Frieren polls enabled hosts concurrently every eight seconds with batch-mode
SSH and short connection timeouts. An unreachable host is shown as offline;
its last-known active sessions are retained instead of being reported as
finished. The collector supports Linux and macOS remote machines with Python 3.

## License

[MIT](LICENSE)
