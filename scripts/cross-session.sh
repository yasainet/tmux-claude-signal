#!/usr/bin/env bash
# Aggregate @claude-signal-state across non-current sessions.
# Output: tmux format string for status-right prepend, or empty.

set -euo pipefail

if ! command -v tmux >/dev/null 2>&1; then
  exit 0
fi

current="${1:-}"

has_needs=0
has_done=0

while IFS='|' read -r sess marker; do
  [ "$sess" = "$current" ] && continue
  case "$marker" in
    needs-input) has_needs=1 ;;
    done)        has_done=1 ;;
  esac
done < <(tmux list-windows -a -F '#{session_name}|#{@claude-signal-state}' 2>/dev/null)

out=""
[ "$has_needs" -eq 1 ] && out+=" #[fg=yellow]●#[default]"
[ "$has_done" -eq 1 ]  && out+=" #[fg=red]●#[default]"
printf '%s' "$out"
