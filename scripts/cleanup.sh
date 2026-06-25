#!/usr/bin/env bash
# Remove stale TMUX_CLAUDE_SIGNAL_* env keys left by older plugin versions.
# Keeps DIR / LOG and unknown shapes (future-proof); drops everything else.

set -euo pipefail

if ! command -v tmux >/dev/null 2>&1; then
  exit 0
fi

# Empty list-windows is a tmux glitch, not a signal that every window is gone.
# Bail out so we don't wipe legitimately-live entries.
existing=$(tmux list-windows -a -F '#{window_id}' 2>/dev/null || true)
[ -z "$existing" ] && exit 0

env_lines=$(tmux show-environment -g 2>/dev/null | grep '^TMUX_CLAUDE_SIGNAL_' || true)
[ -z "$env_lines" ] && exit 0

while IFS= read -r line; do
  key="${line%%=*}"
  case "$key" in
    TMUX_CLAUDE_SIGNAL_DIR|TMUX_CLAUDE_SIGNAL_LOG)
      ;;
    TMUX_CLAUDE_SIGNAL_%*_STATE|TMUX_CLAUDE_SIGNAL_%*_PENDING)
      tmux set-environment -gu "$key" 2>/dev/null || true
      ;;
    TMUX_CLAUDE_SIGNAL_@[0-9]*_STATE|TMUX_CLAUDE_SIGNAL_@[0-9]*_ORIG_*)
      tmux set-environment -gu "$key" 2>/dev/null || true
      ;;
    *)
      ;;
  esac
done <<< "$env_lines"
