# aerospace-queue

A FIFO queue for managing multiple Claude Code sessions across [AeroSpace](https://github.com/nikitabobko/AeroSpace) workspaces on macOS.

## Problem

When running multiple Claude Code sessions, each one periodically needs your attention (permission prompts, task completion, teammate idle). Without a system, you have to manually hunt for the right window.

## How it works

1. **Claude needs attention** → `push.sh` fires as a Claude Code hook
   - Finds the iTerm2 window running the Claude session (via `ITERM_SESSION_ID` + AppleScript)
   - If the window shares a workspace with other windows, moves it to an empty workspace
   - If you're already looking at that workspace, does nothing (no queue, no sound)
   - Warns if multiple terminals end up on the same workspace (ambiguous pop)
   - Otherwise, adds the workspace to a FIFO queue and plays a **Glass** sound
2. **You press `ctrl+alt+cmd+space`** → `pop.sh` fires
   - Plays a **Submarine** sound to acknowledge the keypress
   - Dequeues the oldest workspace and switches to it with a **Pop** sound
   - If you're already on that workspace, silently dequeues (no sound beyond the ack)
   - If the queue is empty, plays a **Tink** sound

## Audio cues

| Sound | Meaning |
|-------|---------|
| Glass | Claude pushed a workspace to the queue |
| Submarine | Pop chord acknowledged |
| Pop | Switched to a queued workspace |
| Tink | Queue is empty, nothing to pop |
| Basso | Push failed (couldn't find the window) |

The `say` voice announcements ("push 3", "pop 3", "queue empty") are temporary training wheels — remove them once you've learned the sounds.

## Setup

### 1. Symlink the AeroSpace config

```bash
ln -sf /Users/brian.buchalter/workspace/aerospace-queue/.aerospace.toml ~/.aerospace.toml
aerospace reload-config
```

### 2. Claude Code hooks (in `~/.claude/settings.json`)

```json
{
  "hooks": {
    "Stop": [{ "hooks": [{ "type": "command", "command": "~/workspace/aerospace-queue/push.sh" }] }],
    "TeammateIdle": [{ "hooks": [{ "type": "command", "command": "~/workspace/aerospace-queue/push.sh" }] }],
    "PermissionRequest": [{ "hooks": [{ "type": "command", "command": "~/workspace/aerospace-queue/push.sh" }] }]
  }
}
```

### 3. AeroSpace keybinding (already in `.aerospace.toml`)

```toml
ctrl-alt-cmd-space = 'exec-and-forget /bin/bash /Users/brian.buchalter/workspace/aerospace-queue/pop.sh'
```

## Important: absolute paths

AeroSpace's `exec-and-forget` runs in a sandboxed environment with no user `$PATH` and restricted process visibility. All paths in `.aerospace.toml` and `pop.sh` must be absolute (e.g., `/usr/bin/afplay`, `/opt/homebrew/bin/aerospace`). `push.sh` runs via Claude Code hooks in a normal shell, but uses absolute paths for consistency.

## Debugging

Both scripts log to `debug.log` in this directory. Check it when things aren't working as expected.

## Requirements

- macOS with [AeroSpace](https://github.com/nikitabobko/AeroSpace) window manager
- [iTerm2](https://iterm2.com/) (uses `ITERM_SESSION_ID` and AppleScript to identify windows)
- [Claude Code](https://claude.ai/code) CLI

## Files

- `push.sh` — Hook script: identifies the terminal window, moves it if needed, queues the workspace
- `pop.sh` — Keybinding script: dequeues and switches to the next workspace
- `queue.txt` — The FIFO queue (one workspace name per line)
- `debug.log` — Runtime log for troubleshooting
- `.aerospace.toml` — AeroSpace config (symlinked from `~/.aerospace.toml`)
