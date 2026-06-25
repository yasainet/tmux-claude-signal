#!/usr/bin/env bash
# Aggregate @claude-signal-state across non-current sessions.
# Output: a complete session-info chip (green bg, icon glyph U+EBC8) when any
# other session is non-idle, else empty. Chip ends with a separator transition
# back to the status bar background and a trailing space.

set -euo pipefail

if ! command -v tmux >/dev/null 2>&1; then
  exit 0
fi

current="${1:-}"

while IFS='|' read -r sess marker; do
  [ "$sess" = "$current" ] && continue
  case "$marker" in
    needs-input|done)
      icon=$''
      printf '#[fg=#15161e,bg=#9ece6a] %s #[fg=#9ece6a,bg=#16161e] ' "$icon"
      exit 0
      ;;
  esac
done < <(tmux list-windows -a -F '#{session_name}|#{@claude-signal-state}' 2>/dev/null)
