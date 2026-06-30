#!/usr/bin/env bash
# A signal is an unread mark for windows you are NOT looking at.
# state.sh must suppress the paint only when you are genuinely viewing the
# pane: an attached client, on that window, with that pane active. Otherwise
# the color lingers with no focus event to clear it, forcing a needless
# leave-and-return to mark it read.
#
# When nothing is attached (e.g. Claude finishing in a detached background
# session) the marker MUST still be set so cross-session.sh can surface it.

set -euo pipefail
source "$(dirname "$0")/lib/test-lib.sh"

setup_tmux
trap teardown_tmux EXIT

_tmux new-window -t test
window_id=$(_tmux display-message -p -t test:2 '#{window_id}')
pane_id=$(_tmux display-message -p -t "$window_id" '#{pane_id}')

echo "  case: detached session still paints (cross-session needs the marker)"
_tmux select-window -t "$window_id"
state_sh "$pane_id" --state done
assert_eq "bg=red,fg=black" "$(get_style "$window_id")" "detached focused window still paints"
assert_eq "done" "$(get_state_marker "$window_id")" "detached focused window keeps marker"
state_sh "$pane_id" --state off

echo "  case: attached + focused pane paints nothing (already read)"
if ! attach_client; then
  printf '  FAIL [attach client]\n    could not attach control-mode client\n' >&2
  _failures=$((_failures + 1))
  report
fi
_tmux select-window -t "$window_id"
state_sh "$pane_id" --state needs-input
assert_empty "$(get_style "$window_id")" "no paint while focused (needs-input)"
assert_empty "$(get_state_marker "$window_id")" "no marker while focused (needs-input)"
state_sh "$pane_id" --state done
assert_empty "$(get_style "$window_id")" "no paint while focused (done)"
assert_empty "$(get_state_marker "$window_id")" "no marker while focused (done)"

echo "  case: attached but viewing another window still paints"
_tmux select-window -t test:1
state_sh "$pane_id" --state done
assert_eq "bg=red,fg=black" "$(get_style "$window_id")" "paints when window not focused"
assert_eq "done" "$(get_state_marker "$window_id")" "marker when window not focused"

report
