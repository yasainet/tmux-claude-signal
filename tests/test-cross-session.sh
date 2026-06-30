#!/usr/bin/env bash
# cross-session.sh always emits a chip; color reflects whether any other
# session is non-idle.

set -euo pipefail
source "$(dirname "$0")/lib/test-lib.sh"

cross_session_sh() {
  local current="$1"
  _tmux run-shell -t test:1 "bash '$TEST_ROOT/scripts/cross-session.sh' '$current' > /tmp/claude-signal-test-cross.$$"
  cat "/tmp/claude-signal-test-cross.$$"
  rm -f "/tmp/claude-signal-test-cross.$$"
}

setup_tmux
trap teardown_tmux EXIT

# Build a second session "other" with one window.
_tmux new-session -d -s other -x 80 -y 24
other_window=$(_tmux display-message -p -t other:1 '#{window_id}')
other_pane=$(_tmux display-message -p -t other:1 '#{pane_id}')

icon=$'⊞'
active="#[fg=#15161e,bg=#9ece6a] ${icon} "
idle="#[fg=#7aa2f7,bg=#3b4261] ${icon} "

echo "  case: no markers anywhere -> idle chip"
assert_eq "$idle" "$(cross_session_sh test)" "all clean -> idle"

echo "  case: needs-input in other session -> active chip"
_tmux set-window-option -qt "$other_window" "@claude-signal-state" "needs-input"
_tmux set-window-option -qt "$other_window" "@claude-signal-pane" "$other_pane"
out=$(cross_session_sh test)
assert_eq "$active" "$out" "needs-input -> active"

echo "  case: done in other session -> active chip"
_tmux set-window-option -qut "$other_window" "@claude-signal-state"
_tmux set-window-option -qt "$other_window" "@claude-signal-state" "done"
out=$(cross_session_sh test)
assert_eq "$active" "$out" "done -> active"

echo "  case: both states across sessions -> active chip"
_tmux new-window -t other
other_window2=$(_tmux display-message -p -t other:2 '#{window_id}')
other_pane2=$(_tmux display-message -p -t other:2 '#{pane_id}')
_tmux set-window-option -qt "$other_window2" "@claude-signal-state" "needs-input"
_tmux set-window-option -qt "$other_window2" "@claude-signal-pane" "$other_pane2"
out=$(cross_session_sh test)
assert_eq "$active" "$out" "any non-idle -> active"

echo "  case: marker on current session only -> idle chip"
_tmux set-window-option -qut "$other_window" "@claude-signal-state"
_tmux set-window-option -qut "$other_window" "@claude-signal-pane"
_tmux set-window-option -qut "$other_window2" "@claude-signal-state"
_tmux set-window-option -qut "$other_window2" "@claude-signal-pane"
test_window=$(_tmux display-message -p -t test:1 '#{window_id}')
test_pane=$(_tmux display-message -p -t test:1 '#{pane_id}')
_tmux set-window-option -qt "$test_window" "@claude-signal-state" "needs-input"
_tmux set-window-option -qt "$test_window" "@claude-signal-pane" "$test_pane"
assert_eq "$idle" "$(cross_session_sh test)" "current session excluded -> idle"
_tmux set-window-option -qut "$test_window" "@claude-signal-state"
_tmux set-window-option -qut "$test_window" "@claude-signal-pane"

echo "  case: stale marker with vanished pane -> idle chip"
_tmux set-window-option -qt "$other_window" "@claude-signal-state" "done"
_tmux set-window-option -qt "$other_window" "@claude-signal-pane" "%9999"
assert_eq "$idle" "$(cross_session_sh test)" "stale pane -> idle"

echo "  case: marker without pane id (legacy) -> idle chip"
_tmux set-window-option -qut "$other_window" "@claude-signal-pane"
assert_eq "$idle" "$(cross_session_sh test)" "no pane id -> idle"

echo "  case: marker with live pane -> active chip"
_tmux set-window-option -qt "$other_window" "@claude-signal-pane" "$other_pane"
assert_eq "$active" "$(cross_session_sh test)" "live pane -> active"

report
