#!/usr/bin/env bash
# Remove stale TMUX_CLAUDE_SIGNAL_* env keys.
#
# Stale = old %N_STATE / %N_PENDING schema (refactor 2722863 で削除済み)
#       + @N_ORIG_* of windows that no longer exist.
# Kept  = TMUX_CLAUDE_SIGNAL_DIR, @N_ORIG_* of live windows, unknown shapes.

set -euo pipefail

if ! command -v tmux >/dev/null 2>&1; then
  exit 0
fi

existing=$(tmux list-windows -a -F '#{window_id}' 2>/dev/null || true)
[ -z "$existing" ] && exit 0

env_lines=$(tmux show-environment -g 2>/dev/null | grep '^TMUX_CLAUDE_SIGNAL_' || true)
[ -z "$env_lines" ] && exit 0

while IFS= read -r line; do
  key="${line%%=*}"
  case "$key" in
    TMUX_CLAUDE_SIGNAL_DIR)
      ;;
    TMUX_CLAUDE_SIGNAL_%*)
      tmux set-environment -gu "$key" 2>/dev/null || true
      ;;
    TMUX_CLAUDE_SIGNAL_@[0-9]*_ORIG_STYLE|TMUX_CLAUDE_SIGNAL_@[0-9]*_ORIG_CURRENT)
      wid=$(printf '%s' "$key" | sed -E 's/^TMUX_CLAUDE_SIGNAL_(@[0-9]+)_.*/\1/')
      [ -z "$wid" ] && continue
      if ! printf '%s\n' "$existing" | grep -qx "$wid"; then
        tmux set-environment -gu "$key" 2>/dev/null || true
      fi
      ;;
    *)
      ;;
  esac
done <<< "$env_lines"
