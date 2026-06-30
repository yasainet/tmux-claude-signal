#!/usr/bin/env bash
# Apply a state to a Claude Code pane's window status color.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=log.sh
. "$SCRIPT_DIR/log.sh"

sig_log "state.sh enter args=$*"
trap 'sig_log "state.sh exit code=$?"' EXIT

usage() {
  cat <<'EOF' >&2
Usage: state.sh --state <needs-input|done|off> [--pane <pane_id>]
EOF
}

if ! command -v tmux >/dev/null 2>&1; then
  exit 0
fi

state=""
pane=""
while [ $# -gt 0 ]; do
  case "$1" in
    --state) state="${2:-}"; shift 2 ;;
    --pane)  pane="${2:-}";  shift 2 ;;
    *) usage; exit 1 ;;
  esac
done

case "$state" in
  needs-input|done|off) ;;
  *) usage; exit 1 ;;
esac

[ -z "$pane" ] && pane="${TMUX_PANE:-}"
[ -z "$pane" ] && exit 0

if ! tmux display-message -p -t "$pane" '#{pane_id}' >/dev/null 2>&1; then
  exit 0
fi

opt_or_default() {
  local key="$1" default="$2" v
  v=$(tmux show-option -gqv "$key" 2>/dev/null || true)
  [ -n "$v" ] && printf '%s' "$v" || printf '%s' "$default"
}

apply_style() {
  local window_id="$1" bg="$2" fg="$3"
  sig_log "APPLY window=$window_id bg=$bg fg=$fg pane=$pane_id"
  tmux set-window-option -qt "$window_id" "window-status-style" "bg=$bg,fg=$fg"
  tmux set-window-option -qt "$window_id" "window-status-current-style" "bg=$bg,fg=$fg"
  tmux set-window-option -qt "$window_id" "@claude-signal-state" "$state"
  tmux set-window-option -qt "$window_id" "@claude-signal-pane" "$pane_id"
}

clear_style() {
  local window_id="$1"
  sig_log "CLEAR window=$window_id"
  tmux set-window-option -qut "$window_id" "window-status-style" || true
  tmux set-window-option -qut "$window_id" "window-status-current-style" || true
  tmux set-window-option -qut "$window_id" "@claude-signal-state" || true
  tmux set-window-option -qut "$window_id" "@claude-signal-pane" || true
}

window_id=$(tmux display-message -p -t "$pane" '#{window_id}')
pane_id=$(tmux display-message -p -t "$pane" '#{pane_id}')
sig_log "state.sh resolve state=$state pane=$pane_id window=$window_id"

needs_bg=$(opt_or_default "@claude-signal-needs-input-bg" "yellow")
needs_fg=$(opt_or_default "@claude-signal-needs-input-fg" "black")
done_bg=$(opt_or_default "@claude-signal-done-bg" "red")
done_fg=$(opt_or_default "@claude-signal-done-fg" "black")

# A signal is an unread mark for windows you are NOT looking at. If the user
# is already viewing this exact pane, painting it would linger with no focus
# event to clear it (focus-ack only fires on a focus *change*), forcing a
# needless leave-and-return to mark it read. Skip the apply in that case.
#
# "Viewing" requires an attached client (session_attached) on this window
# (window_active) with this pane focused (pane_active) -- mirrors focus-ack's
# clear condition. A detached background session is NOT being viewed, so it
# still paints and sets the marker that cross-session.sh surfaces.
# `off` always clears regardless.
is_focused() {
  local pa wa sa
  pa=$(tmux display-message -p -t "$pane_id" '#{pane_active}' 2>/dev/null || echo 0)
  wa=$(tmux display-message -p -t "$window_id" '#{window_active}' 2>/dev/null || echo 0)
  sa=$(tmux display-message -p -t "$pane_id" '#{session_attached}' 2>/dev/null || echo 0)
  [ "$pa" = "1" ] && [ "$wa" = "1" ] && [ "${sa:-0}" -ge 1 ] 2>/dev/null
}

case "$state" in
  needs-input)
    is_focused && { sig_log "SKIP focused window=$window_id pane=$pane_id"; exit 0; }
    apply_style "$window_id" "$needs_bg" "$needs_fg" ;;
  done)
    is_focused && { sig_log "SKIP focused window=$window_id pane=$pane_id"; exit 0; }
    apply_style "$window_id" "$done_bg" "$done_fg" ;;
  off)         clear_style "$window_id" ;;
esac

tmux refresh-client -S >/dev/null 2>&1 || true
