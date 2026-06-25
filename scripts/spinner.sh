#!/usr/bin/env bash
# Print the current spinner frame based on epoch seconds.
# Stateless: called from tmux #() and called fresh each evaluation.

set -euo pipefail

if ! command -v tmux >/dev/null 2>&1; then
  exit 0
fi

tmux_socket=()
if [ -n "${TMUX_SOCKET:-}" ]; then
  tmux_socket=(-L "$TMUX_SOCKET")
fi

frames=$(tmux "${tmux_socket[@]}" show-option -gqv "@claude-signal-running-frames" 2>/dev/null || true)
[ -z "$frames" ] && exit 0

IFS=' ' read -ra arr <<< "$frames"
[ "${#arr[@]}" -eq 0 ] && exit 0

i=$(( $(date +%s) % ${#arr[@]} ))
printf ' %s ' "${arr[$i]}"
