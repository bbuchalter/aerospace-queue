#!/bin/bash

dir="/Users/brian.buchalter/workspace/aerospace-queue"
queue="${dir}/queue.txt"
log="${dir}/debug.log"

log() { printf '%s [pop] %s\n' "$(date '+%H:%M:%S')" "$1" >> "$log"; }

# Acknowledge the command immediately
/usr/bin/afplay /System/Library/Sounds/Submarine.aiff &

log "--- pop.sh started ---"

set -euo pipefail

# No AeroSpace guard needed — this script is only called from an AeroSpace keybinding

if [ ! -f "$queue" ]; then
  touch "$queue"
  log "queue file missing, created empty"
  say "queue empty" &
  /usr/bin/afplay /System/Library/Sounds/Tink.aiff &
  exit 0
fi

first="$(head -n 1 "$queue")"
log "first in queue: '${first}'"
log "queue contents: $(cat "$queue" | tr '\n' ' ')"

if [ -z "$first" ]; then
  log "queue empty"
  say "queue empty" &
  /usr/bin/afplay /System/Library/Sounds/Tink.aiff &
  exit 0
fi

tmp="$(mktemp)"
sed '1d' "$queue" > "$tmp" || true
mv "$tmp" "$queue"
log "dequeued $first, remaining: $(cat "$queue" | tr '\n' ' ')"

# If already on this workspace, just silently dequeue
focused=$(/opt/homebrew/bin/aerospace list-workspaces --focused)
log "focused=$focused target=$first"
if [ "$focused" = "$first" ]; then
  log "already on workspace $first, skipping switch"
  exit 0
fi

/opt/homebrew/bin/aerospace workspace "$first"
log "switched to workspace $first"
say "pop $first" &
/usr/bin/afplay /System/Library/Sounds/Pop.aiff &
log "done"
