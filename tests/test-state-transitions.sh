#!/usr/bin/env bash
# State transitions for a single Claude Code pane.

set -euo pipefail
source "$(dirname "$0")/lib/test-lib.sh"

setup_tmux
trap teardown_tmux EXIT

# Open a second window so we can drive state on a non-active window.
_tmux new-window -t test
window_id=$(_tmux display-message -p -t test:2 '#{window_id}')
pane_id=$(_tmux display-message -p -t "$window_id" '#{pane_id}')
_tmux select-window -t test:1   # focus elsewhere so style applies

echo "  case: initial style is empty"
assert_eq "" "$(get_style "$window_id")" "no style before any state"

echo "  case: needs-input paints yellow"
state_sh "$pane_id" --state needs-input
assert_eq "bg=yellow,fg=black" "$(get_style "$window_id")" "needs-input bg"
assert_eq "bg=yellow,fg=black" "$(get_current_style "$window_id")" "needs-input current"

echo "  case: off clears needs-input"
state_sh "$pane_id" --state off
assert_empty "$(get_style "$window_id")" "off clears style"
assert_empty "$(get_current_style "$window_id")" "off clears current"

echo "  case: done paints red"
state_sh "$pane_id" --state done
assert_eq "bg=red,fg=black" "$(get_style "$window_id")" "done bg"

echo "  case: off clears done"
state_sh "$pane_id" --state off
assert_empty "$(get_style "$window_id")" "off clears style"

echo "  case: running paints default green and sets STATE"
state_sh "$pane_id" --state running
assert_eq "bg=#9ece6a,fg=#15161e" "$(get_style "$window_id")" "running bg default"
assert_eq "bg=#9ece6a,fg=#15161e" "$(get_current_style "$window_id")" "running current default"
assert_eq "running" "$(env_show "TMUX_CLAUDE_SIGNAL_${window_id}_STATE")" "STATE=running"

echo "  case: needs-input after running repaints yellow and unsets STATE"
state_sh "$pane_id" --state needs-input
assert_eq "bg=yellow,fg=black" "$(get_style "$window_id")" "yellow after running"
assert_env_absent "TMUX_CLAUDE_SIGNAL_${window_id}_STATE" "STATE unset after needs-input"

echo "  case: off after running clears bg and unsets STATE"
state_sh "$pane_id" --state running
state_sh "$pane_id" --state off
assert_empty "$(get_style "$window_id")" "off clears running bg"
assert_env_absent "TMUX_CLAUDE_SIGNAL_${window_id}_STATE" "STATE unset after off"

echo "  case: running color is overridable"
_tmux set-option -g "@claude-signal-running-bg" "cyan"
_tmux set-option -g "@claude-signal-running-fg" "white"
state_sh "$pane_id" --state running
assert_eq "bg=cyan,fg=white" "$(get_style "$window_id")" "running bg override"
state_sh "$pane_id" --state off

report
