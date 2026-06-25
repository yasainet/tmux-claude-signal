#!/usr/bin/env bash
# Focusing a done window clears the color (unread-mark semantic).

set -euo pipefail
source "$(dirname "$0")/lib/test-lib.sh"

setup_tmux
trap teardown_tmux EXIT

_tmux new-window -t test
window_id=$(_tmux display-message -p -t test:2 '#{window_id}')
pane_id=$(_tmux display-message -p -t "$window_id" '#{pane_id}')
_tmux select-window -t test:1

echo "  case: done leaves red until focus"
state_sh "$pane_id" --state done
assert_eq "bg=red,fg=black" "$(get_style "$window_id")" "done initial"

echo "  case: focus-ack while target is not active does nothing"
focus_ack_sh "$pane_id" "$window_id"
assert_eq "bg=red,fg=black" "$(get_style "$window_id")" "stale focus-ack ignored"

echo "  case: switching to the window clears red"
_tmux select-window -t "$window_id"
focus_ack_sh "$pane_id" "$window_id"
assert_empty "$(get_style "$window_id")" "focus clears done"

echo "  case: needs-input clears on focus too"
_tmux select-window -t test:1
state_sh "$pane_id" --state needs-input
assert_eq "bg=yellow,fg=black" "$(get_style "$window_id")" "needs-input set"
_tmux select-window -t "$window_id"
focus_ack_sh "$pane_id" "$window_id"
assert_empty "$(get_style "$window_id")" "focus clears needs-input"

echo "  case: focus does not clear running (bg persists)"
_tmux select-window -t test:1
state_sh "$pane_id" --state running
running_bg=$(get_style "$window_id")
assert_eq "bg=#9ece6a,fg=#15161e" "$running_bg" "running bg set"
_tmux select-window -t "$window_id"
focus_ack_sh "$pane_id" "$window_id"
assert_eq "$running_bg" "$(get_style "$window_id")" "running bg survives focus"
assert_eq "running" "$(env_show "TMUX_CLAUDE_SIGNAL_${window_id}_STATE")" "STATE survives focus"

report
