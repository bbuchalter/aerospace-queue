#!/bin/bash
set -euo pipefail

dir="${HOME}/workspace/aerospace-queue"
events="${dir}/events.jsonl"
log="${dir}/debug.log"

log() { printf '%s [status] %s\n' "$(date '+%H:%M:%S')" "$1" >> "$log"; }

state="${1:-}"
if [ -z "$state" ]; then
  log "FAIL: no state argument provided"
  exit 1
fi

log "--- status.sh started with state=$state ---"

/usr/bin/pgrep -qx AeroSpace || { log "AeroSpace not running, exiting"; exit 0; }

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
  exit 1
fi

# Match the window title to an aerospace window and its current workspace
aero_windows=$(/opt/homebrew/bin/aerospace list-windows --all --format '%{window-id} %{workspace} %{window-title}')

read -r window_id current_ws < <(
  echo "$aero_windows" \
    | while IFS=' ' read -r wid ws title; do
        if [ "$title" = "$window_title" ]; then
          echo "$wid $ws"
          break
        fi
      done
)
log "matched window_id=${window_id:-none} current_ws=${current_ws:-none}"

if [ -z "${current_ws:-}" ]; then
  log "FAIL: no workspace found for window"
  exit 1
fi

printf '{"type":"status","workspace":"%s","state":"%s","timestamp":%d}\n' "$current_ws" "$state" "$(date +%s)" >> "$events"
log "wrote status event: workspace=$current_ws state=$state"
