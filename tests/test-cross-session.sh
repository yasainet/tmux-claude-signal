#!/usr/bin/env bash
# cross-session.sh aggregates @claude-signal-state across non-current sessions.

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

echo "  case: no markers anywhere -> empty"
assert_empty "$(cross_session_sh test)" "all clean"

icon='*'
chip="#[fg=#15161e,bg=#9ece6a] ${icon} "

echo "  case: needs-input in other session -> chip emitted"
_tmux set-window-option -qt "$other_window" "@claude-signal-state" "needs-input"
out=$(cross_session_sh test)
assert_eq "$chip" "$out" "needs-input -> chip"

echo "  case: done in other session -> chip emitted"
_tmux set-window-option -qut "$other_window" "@claude-signal-state"
_tmux set-window-option -qt "$other_window" "@claude-signal-state" "done"
out=$(cross_session_sh test)
assert_eq "$chip" "$out" "done -> chip"

echo "  case: both states across sessions -> single chip"
_tmux new-window -t other
other_window2=$(_tmux display-message -p -t other:2 '#{window_id}')
_tmux set-window-option -qt "$other_window2" "@claude-signal-state" "needs-input"
out=$(cross_session_sh test)
assert_eq "$chip" "$out" "any non-idle -> single chip"

echo "  case: marker on current session is ignored"
_tmux set-window-option -qut "$other_window" "@claude-signal-state"
_tmux set-window-option -qut "$other_window2" "@claude-signal-state"
test_window=$(_tmux display-message -p -t test:1 '#{window_id}')
_tmux set-window-option -qt "$test_window" "@claude-signal-state" "needs-input"
assert_empty "$(cross_session_sh test)" "current session excluded"

report
