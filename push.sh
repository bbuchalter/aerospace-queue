#!/bin/bash
set -euo pipefail

dir="${HOME}/workspace/aerospace-queue"
queue="${dir}/queue.txt"
log="${dir}/debug.log"

log() { printf '%s [push] %s\n' "$(date '+%H:%M:%S')" "$1" >> "$log"; }

log "--- push.sh started ---"

/usr/bin/pgrep -qx AeroSpace || { log "AeroSpace not running, exiting"; exit 0; }

if [ ! -f "$queue" ]; then
  touch "$queue"
fi

# Extract the UUID from ITERM_SESSION_ID (format: wXtYpZ:UUID)
session_uuid="${ITERM_SESSION_ID#*:}"
log "ITERM_SESSION_ID=${ITERM_SESSION_ID:-unset}, uuid=$session_uuid"

# Find the iTerm window title for this session via AppleScript
window_title=$(osascript -e "
tell application \"iTerm2\"
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        if unique ID of s is \"$session_uuid\" then
          return name of w
        end if
      end repeat
    end repeat
  end repeat
end tell
" 2>&1)
log "window_title=$window_title"

if [ -z "$window_title" ]; then
  log "FAIL: no window title found"
  say "push failed, no window" &
  /usr/bin/afplay /System/Library/Sounds/Basso.aiff &
  exit 1
fi

# Match the window title to an aerospace window ID and its current workspace
aero_windows=$(/opt/homebrew/bin/aerospace list-windows --all --format '%{window-id} %{workspace} %{window-title}')
log "aerospace windows:"
log "$aero_windows"

# Use command substitution instead of `read < <(...)` — when AeroSpace returns
# empty window titles the subshell produces no output, and `read` exits non-zero
# which `set -e` treats as fatal (killing the script before the friendly guard).
match=$(
  echo "$aero_windows" \
    | while IFS=' ' read -r wid ws title; do
        if [ "$title" = "$window_title" ]; then
          echo "$wid $ws"
          break
        fi
      done
)
window_id="${match%% *}"
current_ws="${match#* }"
log "matched window_id=${window_id:-none} current_ws=${current_ws:-none}"

if [ -z "${window_id:-}" ]; then
  log "FAIL: no aerospace window matched"
  say "push failed, no aerospace window" &
  /usr/bin/afplay /System/Library/Sounds/Basso.aiff &
  exit 1
fi

# If the user is already looking at this workspace, skip the push entirely
focused=$(/opt/homebrew/bin/aerospace list-workspaces --focused)
log "focused=$focused current_ws=$current_ws"
if [ "$focused" = "$current_ws" ]; then
  terminal_count_here=$(/opt/homebrew/bin/aerospace list-windows --workspace "$current_ws" --format '%{app-name}' \
    | grep -c 'iTerm2' || true)
  if [ "$terminal_count_here" -gt 1 ]; then
    log "already focused on workspace $current_ws with $terminal_count_here terminals, move Claude windows to different workspaces"
    say "$terminal_count_here terminals on workspace $current_ws, move Claude windows to different workspaces" &
  else
    log "already focused on this workspace, skipping"
  fi
  /usr/bin/afplay /System/Library/Sounds/Glass.aiff &
  exit 0
fi

# Check if other windows share this workspace — if so, move to an empty one
other_windows=$(/opt/homebrew/bin/aerospace list-windows --workspace "$current_ws" --format '%{window-id}' \
  | grep -cv "^${window_id}$" || true)
log "other_windows on workspace $current_ws: $other_windows"

target_ws="$current_ws"
if [ "$other_windows" -gt 0 ]; then
  occupied=$(/opt/homebrew/bin/aerospace list-windows --all --format '%{workspace}' | sort -u)
  log "occupied workspaces: $(echo $occupied | tr '\n' ' ')"
  for candidate in 1 2 3 4 5 6 7 8 9; do
    if ! echo "$occupied" | grep -qx "$candidate"; then
      target_ws="$candidate"
      break
    fi
  done
  log "moving window $window_id to workspace $target_ws"
  /opt/homebrew/bin/aerospace move-node-to-workspace --window-id "$window_id" "$target_ws"
fi

# Warn if the target workspace has multiple terminals (ambiguous pop)
terminal_count=$(/opt/homebrew/bin/aerospace list-windows --workspace "$target_ws" --format '%{app-name}' \
  | grep -c 'iTerm2' || true)
if [ "$terminal_count" -gt 1 ]; then
  log "WARNING: $terminal_count terminals on workspace $target_ws"
  say "warning, $terminal_count terminals on workspace $target_ws" &
fi

# Only add if not already the last entry (avoid duplicates)
last=$(tail -n 1 "$queue" 2>/dev/null || true)
log "queue last=$last target_ws=$target_ws"
if [ "$last" != "$target_ws" ]; then
  printf '%s\n' "$target_ws" >> "$queue"
  log "queued $target_ws"
else
  log "skipped duplicate"
fi
# Emit structured event for menu bar app
events="${dir}/events.jsonl"
printf '{"type":"push","workspace":"%s","timestamp":%d}\n' "$target_ws" "$(date +%s)" >> "$events"
say "push $target_ws" &
/usr/bin/afplay /System/Library/Sounds/Glass.aiff &
log "done"
