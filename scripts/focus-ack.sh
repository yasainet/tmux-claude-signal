#!/usr/bin/env bash
# Restore the original window-status style when the target pane gains focus.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=log.sh
. "$SCRIPT_DIR/log.sh"

UNSET_SENTINEL="__UNSET__"

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

env_unset() { tmux set-environment -gu "$1" 2>/dev/null || true; }

restore_orig() {
  local opt="$1" env_key="$2" v
  v=$(env_get "$env_key")
  if [ -z "$v" ]; then
    sig_log "focus-ack RESTORE_SKIP opt=$opt key=$env_key (env empty)"
    return
  fi
  if [ "$v" = "$UNSET_SENTINEL" ]; then
    tmux set-window-option -qut "$window_id" "$opt" || true
    sig_log "focus-ack RESTORE_UNSET opt=$opt key=$env_key"
  else
    tmux set-window-option -qt "$window_id" "$opt" "$v"
    sig_log "focus-ack RESTORE_WRITE opt=$opt key=$env_key value=$v"
  fi
  env_unset "$env_key"
}

state_key="TMUX_CLAUDE_SIGNAL_${window_id}_STATE"
state=$(env_get "$state_key")
if [ "$state" = "running" ]; then
  sig_log "focus-ack.sh SKIP running state persists for window=$window_id"
  exit 0
fi

skey="TMUX_CLAUDE_SIGNAL_${window_id}_ORIG_STYLE"
ckey="TMUX_CLAUDE_SIGNAL_${window_id}_ORIG_CURRENT"

restore_orig "window-status-style" "$skey"
restore_orig "window-status-current-style" "$ckey"

tmux refresh-client -S >/dev/null 2>&1 || true
