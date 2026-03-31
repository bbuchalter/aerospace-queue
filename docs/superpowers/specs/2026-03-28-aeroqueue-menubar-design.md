# AeroQueue Menu Bar App

A single-file SwiftUI menu bar app that provides visual monitoring of the aerospace-queue system — showing queue state, workspace status, and activity timeline at a glance.

Inspired by Simon Willison's [vibe-coding SwiftUI](https://simonwillison.net/2026/Mar/27/vibe-coding-swiftui/) approach: one `.swift` file, compiled with `swiftc`, no Xcode.

## Architecture

### Menu Bar Presence

- `NSStatusItem` with a custom SwiftUI view
- Displays an SF Symbol icon (e.g., `tray.fill`) with a queue depth badge number
- Icon tint color reflects state:
  - **Gray** — queue empty, nothing needs attention
  - **Blue** — items in queue, no urgent items
  - **Orange** — at least one workspace in `needsAttention` state
- Clicking opens an `NSPopover` with the main panel

### Popover Panel (~320px wide)

Three sections, top to bottom:

**1. Queue (top)**
- Horizontal chain of workspace badges in FIFO order (e.g., `[3] → [7] → [1]`)
- First badge highlighted (next to pop)
- Shows queue depth in section header
- Keyboard shortcut reminder: `⌘⌥⌃Space to pop`

**2. Workspace Grid (middle)**
- 9-cell single-row grid for workspaces 1–9
- Each cell color-coded by state:
  - **Dim gray** — empty (no windows)
  - **Orange border** — `needsAttention` (waiting for permission/input)
  - **Blue border** — agent actively working
  - **Green border** — agent idle/stopped
  - **Purple border, bold** — currently focused workspace
- Legend row below the grid

**3. Activity Timeline (bottom)**
- Last ~10 events, newest first
- Each row: timestamp, colored indicator, workspace name, event description
- Scrollable if more than visible area

### App Lifecycle

- No dock icon — uses `NSApp.setActivationPolicy(.accessory)`
- Single file: `AeroQueue.swift` in project root
- Compiled with: `swiftc -framework Cocoa -framework SwiftUI AeroQueue.swift -o AeroQueue`
- Run with: `./AeroQueue`

## Data Sources

### 1. Queue State — file watching `queue.txt`

- `DispatchSource.makeFileSystemObjectSource` on `queue.txt`
- On change: read file, parse one workspace name per line
- Feeds: queue contents, queue depth (badge), FIFO ordering
- Existing file format, no changes needed

### 2. Workspace Map — AeroSpace CLI polling

- `Timer` fires every 3 seconds
- Runs: `aerospace list-windows --all --format '%{window-id} %{workspace} %{app-name}'`
- Parses into: `[workspace: [app-name]]` dictionary
- Determines which workspaces have windows and what apps are on them
- Combined with status events to derive per-workspace state

### 3. Activity Events — file watching `events.jsonl`

- New file, appended by push/pop/status scripts
- `DispatchSource` watches for changes, reads new lines since last offset
- Keeps last ~50 events in memory, displays ~10 in timeline
- JSON line format:

```json
{"type":"push","workspace":"3","timestamp":1711612800}
{"type":"pop","workspace":"3","timestamp":1711612830}
{"type":"status","workspace":"3","state":"needsAttention","timestamp":1711612845}
```

#### Event types

| type | fields | emitted by |
|------|--------|------------|
| `push` | `workspace` | `push.sh` after queuing |
| `pop` | `workspace` | `pop.sh` after switching |
| `status` | `workspace`, `state` | hooks via status writing |

#### Status states

| state | meaning | triggered by hook |
|-------|---------|-------------------|
| `needsAttention` | waiting for user input | `PermissionRequest` |
| `idle` | agent idle, not working | `TeammateIdle` |
| `stopped` | agent finished | `Stop` |

## Script Changes

### `push.sh`

- Append a `{"type":"push",...}` JSON line to `events.jsonl` after writing to `queue.txt`
- Update candidate workspace list from `1 2 3 4 5 6 7 8 9 A B C ... Z` to `1 2 3 4 5 6 7 8 9`

### `pop.sh`

- Append a `{"type":"pop",...}` JSON line to `events.jsonl` after dequeuing

### Hook status events

The Claude Code hooks (Stop, TeammateIdle, PermissionRequest) already call `push.sh`. Two options for emitting status events:

**Chosen approach:** Add a `status.sh` script that accepts a state argument and writes to `events.jsonl`. Hooks call both `push.sh` (for queuing) and `status.sh` (for status). This keeps concerns separate — `push.sh` manages the queue, `status.sh` manages status reporting.

```bash
# Example hook config in settings.json:
# PermissionRequest: push.sh && status.sh needsAttention
# TeammateIdle: push.sh && status.sh idle
# Stop: status.sh stopped
```

`status.sh` determines the workspace using the same iTerm2 session → AeroSpace window lookup as `push.sh`.

### `.aerospace.toml`

- Remove persistent workspaces A–Z (keep 1–9 only)
- Remove `alt-a` through `alt-z` workspace switching bindings
- Remove `alt-shift-a` through `alt-shift-z` move-node bindings
- Keep all 1–9 bindings, `alt-tab`, `alt-shift-tab`, and the pop keybinding

### `push.sh` candidate list

Change:
```bash
for candidate in 1 2 3 4 5 6 7 8 9 A B C D E F G I M N O P Q R S T U V W X Y Z; do
```
To:
```bash
for candidate in 1 2 3 4 5 6 7 8 9; do
```

## New Files

| File | Purpose |
|------|---------|
| `AeroQueue.swift` | Single-file SwiftUI menu bar app |
| `events.jsonl` | Append-only event log (created at runtime) |
| `status.sh` | Writes status events to `events.jsonl` |

## Non-Goals

- No Xcode project or `.app` bundle
- No code signing or notarization
- No Launch at Login (future enhancement)
- No click-to-switch-workspace from the popover (future enhancement)
- No event log rotation (file can be manually truncated)
