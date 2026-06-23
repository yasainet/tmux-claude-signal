#!/usr/bin/env bash
# Optional running color: opt-in, persists across focus.

set -euo pipefail
source "$(dirname "$0")/lib/test-lib.sh"

setup_tmux
trap teardown_tmux EXIT

_tmux new-window -t test
window_id=$(_tmux display-message -p -t test:2 '#{window_id}')
pane_id=$(_tmux display-message -p -t "$window_id" '#{pane_id}')
_tmux select-window -t test:1

_tmux set-option -g "@claude-signal-running-bg" "green"
_tmux set-option -g "@claude-signal-running-fg" "black"

echo "  case: running applies configured green"
state_sh "$pane_id" --state running
assert_eq "bg=green,fg=black" "$(get_style "$window_id")" "running green"

echo "  case: focus-ack does not clear running (state indicator persists)"
_tmux select-window -t "$window_id"
focus_ack_sh "$pane_id" "$window_id"
assert_eq "bg=green,fg=black" "$(get_style "$window_id")" "running green stays on focus"

echo "  case: needs-input overrides running"
_tmux select-window -t test:1
state_sh "$pane_id" --state needs-input
assert_eq "bg=yellow,fg=black" "$(get_style "$window_id")" "needs-input over running"

echo "  case: running re-applies green after needs-input"
state_sh "$pane_id" --state running
assert_eq "bg=green,fg=black" "$(get_style "$window_id")" "back to running"

echo "  case: done overrides running"
state_sh "$pane_id" --state done
assert_eq "bg=red,fg=black" "$(get_style "$window_id")" "done over running"

echo "  case: focus clears done (orig __UNSET__ restored, not running)"
_tmux select-window -t "$window_id"
focus_ack_sh "$pane_id" "$window_id"
assert_empty "$(get_style "$window_id")" "done cleared by focus"

echo "  case: running without config still clears (backward compat)"
_tmux set-option -gu "@claude-signal-running-bg"
_tmux set-option -gu "@claude-signal-running-fg"
state_sh "$pane_id" --state needs-input
state_sh "$pane_id" --state running
assert_empty "$(get_style "$window_id")" "running with no config clears"

report
