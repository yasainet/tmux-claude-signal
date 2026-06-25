#!/usr/bin/env bash
# Aggregate @claude-signal-state across non-current sessions.
# Output: a tmux fg-control sequence when any other session is non-idle, else empty.
# Caller follows this with the icon glyph and a fg restore.

set -euo pipefail

if ! command -v tmux >/dev/null 2>&1; then
  exit 0
fi

current="${1:-}"

while IFS='|' read -r sess marker; do
  [ "$sess" = "$current" ] && continue
  case "$marker" in
    needs-input|done)
      printf '#[fg=green]'
      exit 0
      ;;
  esac
done < <(tmux list-windows -a -F '#{session_name}|#{@claude-signal-state}' 2>/dev/null)
