#!/usr/bin/env bash
# A theme-provided window-status-style survives plugin state transitions.

set -euo pipefail
source "$(dirname "$0")/lib/test-lib.sh"

setup_tmux
trap teardown_tmux EXIT

_tmux new-window -t test
window_id=$(_tmux display-message -p -t test:2 '#{window_id}')
pane_id=$(_tmux display-message -p -t "$window_id" '#{pane_id}')
_tmux select-window -t test:1

theme_style="bg=#16161e,fg=#a9b1d6"
_tmux set-window-option -t "$window_id" window-status-style "$theme_style"

echo "  case: theme style intact before state changes"
assert_eq "$theme_style" "$(get_style "$window_id")" "theme baseline"

echo "  case: needs-input overrides theme"
state_sh "$pane_id" --state needs-input
assert_eq "bg=yellow,fg=black" "$(get_style "$window_id")" "needs-input override"

echo "  case: running restores theme style"
state_sh "$pane_id" --state running
assert_eq "$theme_style" "$(get_style "$window_id")" "theme restored after running"

echo "  case: done overrides, focus restores theme"
state_sh "$pane_id" --state done
assert_eq "bg=red,fg=black" "$(get_style "$window_id")" "done override"
_tmux select-window -t "$window_id"
focus_ack_sh "$pane_id" "$window_id"
assert_eq "$theme_style" "$(get_style "$window_id")" "theme restored after focus"

report
