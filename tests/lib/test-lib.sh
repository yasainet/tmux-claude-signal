#!/usr/bin/env bash
# Shared helpers for tmux-claude-signal tests.

set -euo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_SOCKET="claude-signal-test-$$"

_failures=0

TEST_CONF="$(mktemp -t claude-signal-test-conf.XXXXXX)"
printf 'set -g base-index 1\n' > "$TEST_CONF"

_tmux() { tmux -L "$TEST_SOCKET" -f "$TEST_CONF" "$@"; }

setup_tmux() {
  _tmux kill-server 2>/dev/null || true
  _tmux new-session -d -s test -x 80 -y 24
  _tmux set-environment -g TMUX_CLAUDE_SIGNAL_DIR "$TEST_ROOT"
}

teardown_tmux() {
  _tmux kill-server 2>/dev/null || true
  rm -f "$TEST_CONF"
}

state_sh() {
  local pane_id="$1"; shift
  _tmux run-shell "bash '$TEST_ROOT/scripts/state.sh' --pane $pane_id $*"
}

focus_ack_sh() {
  local pane_id="$1" window_id="$2"
  _tmux run-shell "bash '$TEST_ROOT/scripts/focus-ack.sh' $pane_id $window_id"
}

get_style() {
  local window_id="$1"
  _tmux show-options -wqv -t "$window_id" window-status-style 2>/dev/null || true
}

get_current_style() {
  local window_id="$1"
  _tmux show-options -wqv -t "$window_id" window-status-current-style 2>/dev/null || true
}

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [ "$expected" != "$actual" ]; then
    printf '  FAIL [%s]\n    expected: %q\n    actual:   %q\n' \
      "$msg" "$expected" "$actual" >&2
    _failures=$((_failures + 1))
    return 1
  fi
  return 0
}

assert_empty() {
  local actual="$1" msg="${2:-}"
  if [ -n "$actual" ]; then
    printf '  FAIL [%s]\n    expected: <empty>\n    actual:   %q\n' \
      "$msg" "$actual" >&2
    _failures=$((_failures + 1))
    return 1
  fi
  return 0
}

cleanup_sh() {
  _tmux run-shell "bash '$TEST_ROOT/scripts/cleanup.sh'"
}

env_show() {
  local name="$1"
  _tmux show-environment -g "$name" 2>/dev/null | sed 's/^[^=]*=//' || true
}

assert_env_absent() {
  local name="$1" msg="${2:-}"
  local out
  out=$(_tmux show-environment -g "$name" 2>&1) || true
  case "$out" in
    "unknown variable: "*) return 0 ;;
  esac
  printf '  FAIL [%s]\n    expected env %s absent\n    actual:   %s\n' \
    "$msg" "$name" "$out" >&2
  _failures=$((_failures + 1))
  return 1
}

report() {
  if [ "$_failures" -gt 0 ]; then
    printf 'FAILED (%d assertion(s))\n' "$_failures" >&2
    exit 1
  fi
  echo "ok"
}
