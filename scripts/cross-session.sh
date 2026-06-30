#!/usr/bin/env bash
# Aggregate @claude-signal-state across non-current sessions.
# Output: a session-info chip always shown.
# Color reflects whether any other session is non-idle:
#   - active (any needs-input/done elsewhere): green bg, dark fg
#   - idle (everything quiet):                 muted blue bg, blue fg
# Icon is ⊞ (U+229E). Padding is leading 1 + trailing 1.

set -euo pipefail

if ! command -v tmux >/dev/null 2>&1; then
  exit 0
fi

current="${1:-}"

has_any=0
while IFS='|' read -r sess marker pane_id; do
  [ "$sess" = "$current" ] && continue
  case "$marker" in
    needs-input|done) ;;
    *) continue ;;
  esac
  [ -z "$pane_id" ] && continue
  resolved=$(tmux display-message -p -t "$pane_id" '#{pane_id}' 2>/dev/null || true)
  [ -z "$resolved" ] && continue
  has_any=1
  break
done < <(tmux list-windows -a -F '#{session_name}|#{@claude-signal-state}|#{@claude-signal-pane}' 2>/dev/null)

icon=$'⊞'
if [ "$has_any" -eq 1 ]; then
  printf '#[fg=#15161e,bg=#9ece6a] %s ' "$icon"
else
  printf '#[fg=#7aa2f7,bg=#3b4261] %s ' "$icon"
fi
