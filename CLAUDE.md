# aerospace-queue

FIFO queue for routing attention across AeroSpace workspaces when Claude Code needs input.

## Architecture

- `push.sh` — Claude Code hook. Identifies the iTerm2 window via `ITERM_SESSION_ID` + AppleScript, moves it to an empty workspace if sharing one, queues the workspace.
- `pop.sh` — AeroSpace keybinding (`ctrl+alt+cmd+space`). Dequeues the oldest workspace and switches to it.
- `queue.txt` — One workspace name per line, FIFO order.
- `.aerospace.toml` — AeroSpace config with the pop keybinding. `~/.aerospace.toml` is a symlink to this file.

## Conventions

- Always use absolute paths (not `~`) in `.aerospace.toml` bindings and in `push.sh`/`pop.sh`. AeroSpace's `exec-and-forget` may not expand `~`.
- Always use absolute paths for ALL binaries — in `.aerospace.toml`, `push.sh`, and `pop.sh` (e.g., `/usr/bin/afplay`, `/usr/bin/pgrep`, `/opt/homebrew/bin/aerospace`). AeroSpace's `exec-and-forget` does not inherit the user's `$PATH`.
- AeroSpace's `exec-and-forget` runs in a sandboxed environment where `pgrep` cannot see other processes. Do not use `pgrep` guards in scripts called from AeroSpace keybindings. The `pgrep` guard in `push.sh` is fine because it runs via Claude Code hooks (normal shell environment).
- Scripts must work with macOS `/bin/bash` (v3) — no associative arrays, no bash 4+ features.
- Audio cues: Glass = push, Pop = pop, Tink = empty queue, Basso = error.
- `say` announcements are temporary training wheels. Remove them once the sounds are learned.

## Hook integration

`push.sh` is called from `~/.claude/settings.json` hooks: `Stop`, `TeammateIdle`, `PermissionRequest`.

## Dependencies

- AeroSpace (window manager) — `pgrep -qx AeroSpace` guards both scripts
- iTerm2 — uses `ITERM_SESSION_ID` env var and AppleScript API
- macOS system sounds via `afplay`
