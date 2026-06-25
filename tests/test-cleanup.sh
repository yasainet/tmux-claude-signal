#!/usr/bin/env bash
# cleanup.sh removes stale TMUX_CLAUDE_SIGNAL_* keys and preserves live ones.

set -euo pipefail
source "$(dirname "$0")/lib/test-lib.sh"

setup_tmux
trap teardown_tmux EXIT

live_window=$(_tmux display-message -p '#{window_id}')

_tmux set-environment -g 'TMUX_CLAUDE_SIGNAL_%11_STATE' done
_tmux set-environment -g 'TMUX_CLAUDE_SIGNAL_%11_PENDING' 1
_tmux set-environment -g 'TMUX_CLAUDE_SIGNAL_@999_ORIG_STYLE' __UNSET__
_tmux set-environment -g 'TMUX_CLAUDE_SIGNAL_@999_ORIG_CURRENT' __UNSET__
_tmux set-environment -g "TMUX_CLAUDE_SIGNAL_${live_window}_ORIG_STYLE" __UNSET__
_tmux set-environment -g TMUX_CLAUDE_SIGNAL_DIR /test/path
_tmux set-environment -g TMUX_CLAUDE_SIGNAL_FUTURE_FOO bar

echo "  case: cleanup removes stale, keeps live + DIR + unknown"
cleanup_sh

assert_env_absent 'TMUX_CLAUDE_SIGNAL_%11_STATE'    "old % STATE removed"
assert_env_absent 'TMUX_CLAUDE_SIGNAL_%11_PENDING'  "old % PENDING removed"
assert_env_absent 'TMUX_CLAUDE_SIGNAL_@999_ORIG_STYLE'   "gone window STYLE removed"
assert_env_absent 'TMUX_CLAUDE_SIGNAL_@999_ORIG_CURRENT' "gone window CURRENT removed"
assert_eq "__UNSET__" "$(env_show "TMUX_CLAUDE_SIGNAL_${live_window}_ORIG_STYLE")" "live window kept"
assert_eq "/test/path" "$(env_show TMUX_CLAUDE_SIGNAL_DIR)" "DIR kept"
assert_eq "bar"        "$(env_show TMUX_CLAUDE_SIGNAL_FUTURE_FOO)" "unknown kept"

report
