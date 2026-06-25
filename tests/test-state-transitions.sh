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

echo "  case: running without frames → no-op"
_tmux set-window-option -t "$window_id" window-status-format "#I:#W"
state_sh "$pane_id" --state running
assert_eq "#I:#W" "$(_tmux show-options -wqv -t "$window_id" window-status-format)" "format untouched without frames"
assert_env_absent "TMUX_CLAUDE_SIGNAL_${window_id}_STATE" "STATE not set without frames"

echo "  case: running with frames → format wrap and STATE set"
_tmux set-option -g "@claude-signal-running-frames" "A B"
state_sh "$pane_id" --state running
fmt=$(_tmux show-options -wqv -t "$window_id" window-status-format)
case "$fmt" in
  *"#(${TEST_ROOT}/scripts/spinner.sh)"*) ;;
  *) printf '  FAIL [format not wrapped: %q]\n' "$fmt" >&2; _failures=$((_failures + 1)) ;;
esac
assert_eq "running" "$(env_show "TMUX_CLAUDE_SIGNAL_${window_id}_STATE")" "STATE=running"
assert_empty "$(get_style "$window_id")" "running clears bg"

echo "  case: needs-input after running restores format and unsets STATE"
state_sh "$pane_id" --state needs-input
assert_eq "#I:#W" "$(_tmux show-options -wqv -t "$window_id" window-status-format)" "format restored"
assert_env_absent "TMUX_CLAUDE_SIGNAL_${window_id}_STATE" "STATE unset after needs-input"

echo "  case: off after running restores format and unsets STATE"
state_sh "$pane_id" --state running
state_sh "$pane_id" --state off
assert_eq "#I:#W" "$(_tmux show-options -wqv -t "$window_id" window-status-format)" "format restored after off"
assert_env_absent "TMUX_CLAUDE_SIGNAL_${window_id}_STATE" "STATE unset after off"

report
