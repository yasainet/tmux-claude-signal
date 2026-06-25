#!/usr/bin/env bash
# tmux-claude-signal: window-status color signal for Claude Code panes.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tmux set-environment -g TMUX_CLAUDE_SIGNAL_DIR "$CURRENT_DIR"

focus_cmd="run-shell \"$CURRENT_DIR/scripts/focus-ack.sh \\\"#{pane_id}\\\" \\\"#{window_id}\\\"\""

# Replace any prior plugin hook to avoid duplicates on reload.
for hook in pane-focus-in after-select-window after-select-pane; do
  existing=$(tmux show-hooks -g "$hook" 2>/dev/null | grep -F "$CURRENT_DIR" || true)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    name="${line%% *}"
    tmux set-hook -gu "$name" 2>/dev/null || true
  done <<< "$existing"
  tmux set-hook -ag "$hook" "$focus_cmd"
done

tmux run-shell "$CURRENT_DIR/scripts/cleanup.sh" 2>/dev/null || true
