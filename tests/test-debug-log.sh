#!/usr/bin/env bash
# Debug log opt-in via @claude-signal-debug.

set -euo pipefail
source "$(dirname "$0")/lib/test-lib.sh"

setup_tmux
trap teardown_tmux EXIT

_tmux new-window -t test
window_id=$(_tmux display-message -p -t test:2 '#{window_id}')
pane_id=$(_tmux display-message -p -t "$window_id" '#{pane_id}')

log_path="$(mktemp -t claude-signal-test-log.XXXXXX)"
rm -f "$log_path"
_tmux set-environment -g TMUX_CLAUDE_SIGNAL_LOG "$log_path"

assert_no_log() {
  local msg="$1"
  if [ -f "$log_path" ]; then
    printf '  FAIL [%s]\n    log file unexpectedly exists: %s\n    contents:\n%s\n' \
      "$msg" "$log_path" "$(cat "$log_path")" >&2
    _failures=$((_failures + 1))
    return 1
  fi
}

assert_log_has() {
  local pattern="$1" msg="$2"
  if ! [ -f "$log_path" ]; then
    printf '  FAIL [%s]\n    log file missing: %s\n' "$msg" "$log_path" >&2
    _failures=$((_failures + 1))
    return 1
  fi
  if ! grep -qE "$pattern" "$log_path"; then
    printf '  FAIL [%s]\n    pattern %q not found in log\n    contents:\n%s\n' \
      "$msg" "$pattern" "$(cat "$log_path")" >&2
    _failures=$((_failures + 1))
    return 1
  fi
}

echo "  case: debug off → state.sh writes no log"
state_sh "$pane_id" --state done
assert_no_log "debug off, state.sh"

echo "  case: debug off → focus-ack.sh writes no log"
_tmux select-window -t "$window_id"
focus_ack_sh "$pane_id" "$window_id"
assert_no_log "debug off, focus-ack.sh"

echo "  case: debug on → state.sh records enter line with state and pane"
_tmux set-option -g "@claude-signal-debug" "1"
state_sh "$pane_id" --state done
assert_log_has "state\.sh.*enter" "state.sh enter line"
assert_log_has "\-\-state done" "state.sh records state value"
assert_log_has "\-\-pane $pane_id" "state.sh records pane id"

echo "  case: debug on → focus-ack.sh records enter line with window"
_tmux select-window -t test:1
_tmux select-window -t "$window_id"
focus_ack_sh "$pane_id" "$window_id"
assert_log_has "focus-ack\.sh.*enter" "focus-ack.sh enter line"
assert_log_has "window=$window_id" "focus-ack.sh records window id"

echo "  case: TMUX_CLAUDE_SIGNAL_LOG overrides default path"
# already exercised above — log_path is a non-default mktemp; existence proves override
[ -f "$log_path" ] || {
  printf '  FAIL [override path]\n    log_path %s missing\n' "$log_path" >&2
  _failures=$((_failures + 1))
}

rm -f "$log_path"
report
