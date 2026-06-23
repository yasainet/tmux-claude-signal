#!/usr/bin/env bash
# Clear pending state colors when the target pane actually gains focus.

set -euo pipefail

UNSET_SENTINEL="__UNSET__"

pane_id="${1:-}"
window_id="${2:-}"

if ! command -v tmux >/dev/null 2>&1; then
  exit 0
fi

[ -z "$pane_id" ] && pane_id=$(tmux display-message -p '#{pane_id}')
[ -z "$window_id" ] && window_id=$(tmux display-message -p -t "$pane_id" '#{window_id}' 2>/dev/null || true)
[ -z "$window_id" ] && exit 0

pane_active=$(tmux display-message -p -t "$pane_id" '#{pane_active}' 2>/dev/null || echo 0)
window_active=$(tmux display-message -p -t "$window_id" '#{window_active}' 2>/dev/null || echo 0)
[ "$pane_active" = "1" ] || exit 0
[ "$window_active" = "1" ] || exit 0

env_get() {
  tmux show-environment -g "$1" 2>/dev/null | sed 's/^[^=]*=//' || true
}

env_unset() { tmux set-environment -gu "$1" 2>/dev/null || true; }

restore_orig() {
  local opt="$1" env_key="$2" v
  v=$(env_get "$env_key")
  [ -z "$v" ] && return
  if [ "$v" = "$UNSET_SENTINEL" ]; then
    tmux set-window-option -qut "$window_id" "$opt" || true
  else
    tmux set-window-option -qt "$window_id" "$opt" "$v"
  fi
  env_unset "$env_key"
}

state_key="TMUX_CLAUDE_SIGNAL_${pane_id}_STATE"
pending_key="TMUX_CLAUDE_SIGNAL_${pane_id}_PENDING"
skey="TMUX_CLAUDE_SIGNAL_${window_id}_ORIG_STYLE"
ckey="TMUX_CLAUDE_SIGNAL_${window_id}_ORIG_CURRENT"

state=$(env_get "$state_key")
pending=$(env_get "$pending_key")

if [ "$state" = "needs-input" ] || [ "$state" = "done" ] || [ "$pending" = "1" ]; then
  restore_orig "window-status-style" "$skey"
  restore_orig "window-status-current-style" "$ckey"
  env_unset "$state_key"
  env_unset "$pending_key"
fi

tmux refresh-client -S >/dev/null 2>&1 || true
