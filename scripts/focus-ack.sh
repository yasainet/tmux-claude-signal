#!/usr/bin/env bash
# Clear the signal color when the target pane gains focus.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=log.sh
. "$SCRIPT_DIR/log.sh"

pane_id="${1:-}"
window_id="${2:-}"

sig_log "focus-ack.sh enter pane=$pane_id window=$window_id"
trap 'sig_log "focus-ack.sh exit code=$?"' EXIT

if ! command -v tmux >/dev/null 2>&1; then
  exit 0
fi

[ -z "$pane_id" ] && pane_id=$(tmux display-message -p '#{pane_id}')
[ -z "$window_id" ] && window_id=$(tmux display-message -p -t "$pane_id" '#{window_id}' 2>/dev/null || true)
[ -z "$window_id" ] && exit 0

pane_active=$(tmux display-message -p -t "$pane_id" '#{pane_active}' 2>/dev/null || echo 0)
window_active=$(tmux display-message -p -t "$window_id" '#{window_active}' 2>/dev/null || echo 0)
sig_log "focus-ack.sh ACTIVE pane_active=$pane_active window_active=$window_active"
[ "$pane_active" = "1" ] || { sig_log "focus-ack.sh ABORT pane not active"; exit 0; }
[ "$window_active" = "1" ] || { sig_log "focus-ack.sh ABORT window not active"; exit 0; }

env_get() {
  tmux show-environment -g "$1" 2>/dev/null | sed 's/^[^=]*=//' || true
}

state_key="TMUX_CLAUDE_SIGNAL_${window_id}_STATE"
state=$(env_get "$state_key")
if [ "$state" = "running" ]; then
  sig_log "focus-ack.sh SKIP running state persists for window=$window_id"
  exit 0
fi

sig_log "focus-ack CLEAR window=$window_id"
tmux set-window-option -qut "$window_id" "window-status-style" || true
tmux set-window-option -qut "$window_id" "window-status-current-style" || true

tmux refresh-client -S >/dev/null 2>&1 || true
