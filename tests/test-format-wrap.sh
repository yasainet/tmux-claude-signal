#!/usr/bin/env bash
# Verify wrap_format handles common themes and falls back safely.

set -euo pipefail
source "$(dirname "$0")/lib/test-lib.sh"

setup_tmux
trap teardown_tmux EXIT

_tmux new-window -t test
window_id=$(_tmux display-message -p -t test:2 '#{window_id}')
pane_id=$(_tmux display-message -p -t "$window_id" '#{pane_id}')
_tmux select-window -t test:1

_tmux set-option -g "@claude-signal-running-frames" "A B C"

spinner_cmd="#(${TEST_ROOT}/scripts/spinner.sh)"

assert_wrap() {
  local input="$1" expected="$2" label="$3"
  _tmux set-window-option -t "$window_id" window-status-format "$input"
  # ensure we get a fresh ORIG_FORMAT each case
  _tmux set-environment -gu "TMUX_CLAUDE_SIGNAL_${window_id}_ORIG_FORMAT" 2>/dev/null || true
  state_sh "$pane_id" --state running
  assert_eq "$expected" "$(_tmux show-options -wqv -t "$window_id" window-status-format)" "$label"
  state_sh "$pane_id" --state off
}

echo "  case: #I:#W → spinner replaces colon"
assert_wrap "#I:#W" "#I${spinner_cmd}#W" "colon sep"

echo "  case: #I  #W → spinner replaces double space"
assert_wrap "#I  #W" "#I${spinner_cmd}#W" "spaces sep"

echo "  case: #I #W#F → spinner replaces single space, #F stays"
assert_wrap "#I #W#F" "#I${spinner_cmd}#W#F" "space with trailing flag"

echo "  case: no #I/#W → fallback full replace"
assert_wrap "#{window_index}:#{window_name}" "#I ${spinner_cmd} #W" "fallback"

report
