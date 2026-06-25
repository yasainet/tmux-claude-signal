#!/usr/bin/env bash
# Apply a state to a Claude Code pane's window status color.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=log.sh
. "$SCRIPT_DIR/log.sh"

sig_log "state.sh enter args=$*"
trap 'sig_log "state.sh exit code=$?"' EXIT

UNSET_SENTINEL="__UNSET__"

usage() {
  cat <<'EOF' >&2
Usage: state.sh --state <running|needs-input|done|off> [--pane <pane_id>]
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
  running|needs-input|done|off) ;;
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

env_get() {
  tmux show-environment -g "$1" 2>/dev/null | sed 's/^[^=]*=//' || true
}

env_set() { tmux set-environment -g "$1" "$2"; }
env_unset() { tmux set-environment -gu "$1" 2>/dev/null || true; }

save_orig_once() {
  local window_id="$1" opt="$2" env_key="$3" v
  if [ -n "$(env_get "$env_key")" ]; then
    sig_log "save_orig_once SKIP window=$window_id opt=$opt key=$env_key (already set)"
    return
  fi
  v=$(tmux show-options -wqv -t "$window_id" "$opt" 2>/dev/null || true)
  if [ -z "$v" ]; then
    env_set "$env_key" "$UNSET_SENTINEL"
    sig_log "save_orig_once SET   window=$window_id opt=$opt key=$env_key value=<UNSET>"
  else
    env_set "$env_key" "$v"
    sig_log "save_orig_once SET   window=$window_id opt=$opt key=$env_key value=$v"
  fi
}

restore_orig() {
  local window_id="$1" opt="$2" env_key="$3" v
  v=$(env_get "$env_key")
  if [ -z "$v" ]; then
    sig_log "restore_orig SKIP  window=$window_id opt=$opt key=$env_key (env empty)"
    return
  fi
  if [ "$v" = "$UNSET_SENTINEL" ]; then
    tmux set-window-option -qut "$window_id" "$opt" || true
    sig_log "restore_orig UNSET window=$window_id opt=$opt key=$env_key"
  else
    tmux set-window-option -qt "$window_id" "$opt" "$v"
    sig_log "restore_orig WRITE window=$window_id opt=$opt key=$env_key value=$v"
  fi
  env_unset "$env_key"
}

apply_style() {
  local window_id="$1" bg="$2" fg="$3"
  local skey="TMUX_CLAUDE_SIGNAL_${window_id}_ORIG_STYLE"
  local ckey="TMUX_CLAUDE_SIGNAL_${window_id}_ORIG_CURRENT"
  sig_log "APPLY window=$window_id bg=$bg fg=$fg"
  save_orig_once "$window_id" "window-status-style" "$skey"
  save_orig_once "$window_id" "window-status-current-style" "$ckey"
  tmux set-window-option -qt "$window_id" "window-status-style" "bg=$bg,fg=$fg"
  tmux set-window-option -qt "$window_id" "window-status-current-style" "bg=$bg,fg=$fg"
}

clear_style() {
  local window_id="$1"
  local skey="TMUX_CLAUDE_SIGNAL_${window_id}_ORIG_STYLE"
  local ckey="TMUX_CLAUDE_SIGNAL_${window_id}_ORIG_CURRENT"
  sig_log "CLEAR window=$window_id"
  restore_orig "$window_id" "window-status-style" "$skey"
  restore_orig "$window_id" "window-status-current-style" "$ckey"
}

wrap_format() {
  local window_id="$1"
  local spinner_cmd="#(${SCRIPT_DIR}/spinner.sh)"
  local fkey="TMUX_CLAUDE_SIGNAL_${window_id}_ORIG_FORMAT"

  save_orig_once "$window_id" "window-status-format" "$fkey"

  local fmt
  fmt=$(tmux show-options -wqv -t "$window_id" window-status-format 2>/dev/null || true)
  if [ -z "$fmt" ]; then
    fmt=$(tmux show-options -gqv window-status-format 2>/dev/null || true)
  fi

  local new_fmt
  if [[ "$fmt" =~ \#I([^#]*)\#W ]]; then
    local sep="${BASH_REMATCH[1]}"
    new_fmt="${fmt//"#I${sep}#W"/"#I${spinner_cmd}#W"}"
  else
    new_fmt="#I ${spinner_cmd} #W"
  fi
  tmux set-window-option -qt "$window_id" window-status-format "$new_fmt"
}

restore_format() {
  local window_id="$1"
  local fkey="TMUX_CLAUDE_SIGNAL_${window_id}_ORIG_FORMAT"
  restore_orig "$window_id" "window-status-format" "$fkey"
}

window_id=$(tmux display-message -p -t "$pane" '#{window_id}')
state_key="TMUX_CLAUDE_SIGNAL_${window_id}_STATE"
sig_log "state.sh resolve state=$state pane=$pane window=$window_id"

running_frames=$(opt_or_default "@claude-signal-running-frames" "")
needs_bg=$(opt_or_default "@claude-signal-needs-input-bg" "yellow")
needs_fg=$(opt_or_default "@claude-signal-needs-input-fg" "black")
done_bg=$(opt_or_default "@claude-signal-done-bg" "red")
done_fg=$(opt_or_default "@claude-signal-done-fg" "black")

case "$state" in
  running)
    if [ -n "$running_frames" ]; then
      env_set "$state_key" "running"
      clear_style "$window_id"
      wrap_format "$window_id"
    fi
    ;;
  needs-input)
    env_unset "$state_key"
    restore_format "$window_id"
    apply_style "$window_id" "$needs_bg" "$needs_fg"
    ;;
  done)
    env_unset "$state_key"
    restore_format "$window_id"
    apply_style "$window_id" "$done_bg" "$done_fg"
    ;;
  off)
    env_unset "$state_key"
    restore_format "$window_id"
    clear_style "$window_id"
    ;;
esac

tmux refresh-client -S >/dev/null 2>&1 || true
