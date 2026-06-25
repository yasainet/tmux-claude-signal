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
  sig_log "APPLY window=$window_id bg=$bg fg=$fg"
  tmux set-window-option -qt "$window_id" "window-status-style" "bg=$bg,fg=$fg"
  tmux set-window-option -qt "$window_id" "window-status-current-style" "bg=$bg,fg=$fg"
}

clear_style() {
  local window_id="$1"
  sig_log "CLEAR window=$window_id"
  tmux set-window-option -qut "$window_id" "window-status-style" || true
  tmux set-window-option -qut "$window_id" "window-status-current-style" || true
}

window_id=$(tmux display-message -p -t "$pane" '#{window_id}')
sig_log "state.sh resolve state=$state pane=$pane window=$window_id"

needs_bg=$(opt_or_default "@claude-signal-needs-input-bg" "yellow")
needs_fg=$(opt_or_default "@claude-signal-needs-input-fg" "black")
done_bg=$(opt_or_default "@claude-signal-done-bg" "red")
done_fg=$(opt_or_default "@claude-signal-done-fg" "black")

case "$state" in
  needs-input) apply_style "$window_id" "$needs_bg" "$needs_fg" ;;
  done)        apply_style "$window_id" "$done_bg" "$done_fg" ;;
  off)         clear_style "$window_id" ;;
esac

tmux refresh-client -S >/dev/null 2>&1 || true
