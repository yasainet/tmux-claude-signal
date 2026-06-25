#!/usr/bin/env bash
# cleanup.sh removes stale TMUX_CLAUDE_SIGNAL_* keys and preserves live ones.

set -euo pipefail
source "$(dirname "$0")/lib/test-lib.sh"

setup_tmux
trap 'teardown_tmux; rm -rf "${FAKE_DIR:-}"' EXIT

live_window=$(_tmux display-message -p '#{window_id}')

# STATE keys: stale (gone window) vs live
_tmux set-environment -g 'TMUX_CLAUDE_SIGNAL_@999_STATE' running
_tmux set-environment -g "TMUX_CLAUDE_SIGNAL_${live_window}_STATE" running

# Legacy ORIG_* keys: removed unconditionally (env-less restore 採用後)
_tmux set-environment -g 'TMUX_CLAUDE_SIGNAL_@999_ORIG_STYLE' __UNSET__
_tmux set-environment -g 'TMUX_CLAUDE_SIGNAL_@999_ORIG_CURRENT' __UNSET__
_tmux set-environment -g 'TMUX_CLAUDE_SIGNAL_@999_ORIG_FORMAT' '#I:#W'
_tmux set-environment -g "TMUX_CLAUDE_SIGNAL_${live_window}_ORIG_STYLE" __UNSET__
_tmux set-environment -g "TMUX_CLAUDE_SIGNAL_${live_window}_ORIG_FORMAT" '#I:#W'

# Old % schema
_tmux set-environment -g 'TMUX_CLAUDE_SIGNAL_%11_STATE' done
_tmux set-environment -g 'TMUX_CLAUDE_SIGNAL_%11_PENDING' 1

# Preserved keys
_tmux set-environment -g TMUX_CLAUDE_SIGNAL_DIR /test/path
_tmux set-environment -g TMUX_CLAUDE_SIGNAL_LOG /tmp/some.log
_tmux set-environment -g TMUX_CLAUDE_SIGNAL_FUTURE_FOO bar

echo "  case: cleanup removes stale + all ORIG_*, keeps live STATE + DIR + LOG + unknown"
cleanup_sh

assert_env_absent 'TMUX_CLAUDE_SIGNAL_%11_STATE'    "old % STATE removed"
assert_env_absent 'TMUX_CLAUDE_SIGNAL_%11_PENDING'  "old % PENDING removed"
assert_env_absent 'TMUX_CLAUDE_SIGNAL_@999_ORIG_STYLE'   "gone window ORIG_STYLE removed"
assert_env_absent 'TMUX_CLAUDE_SIGNAL_@999_ORIG_CURRENT' "gone window ORIG_CURRENT removed"
assert_env_absent 'TMUX_CLAUDE_SIGNAL_@999_ORIG_FORMAT'  "gone window ORIG_FORMAT removed"
assert_env_absent 'TMUX_CLAUDE_SIGNAL_@999_STATE'        "gone window STATE removed"
assert_env_absent "TMUX_CLAUDE_SIGNAL_${live_window}_ORIG_STYLE"  "live window ORIG_STYLE removed (env-less)"
assert_env_absent "TMUX_CLAUDE_SIGNAL_${live_window}_ORIG_FORMAT" "live window ORIG_FORMAT removed (env-less)"
assert_eq "running"  "$(env_show "TMUX_CLAUDE_SIGNAL_${live_window}_STATE")"       "live window STATE kept"
assert_eq "/test/path" "$(env_show TMUX_CLAUDE_SIGNAL_DIR)" "DIR kept"
assert_eq "/tmp/some.log" "$(env_show TMUX_CLAUDE_SIGNAL_LOG)" "LOG kept"
assert_eq "bar"        "$(env_show TMUX_CLAUDE_SIGNAL_FUTURE_FOO)" "unknown kept"

echo "  case: list-windows empty makes cleanup a no-op"
# Re-seed one of the stale keys so we have something to detect non-removal.
_tmux set-environment -g 'TMUX_CLAUDE_SIGNAL_%11_STATE' done

# Build a fake tmux on PATH that returns empty for `list-windows -a` and
# delegates everything else to the real tmux.
FAKE_DIR="$(mktemp -d -t claude-signal-fake-XXXXXX)"
REAL_TMUX="$(command -v tmux)"
cat > "$FAKE_DIR/tmux" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "list-windows" ]; then
  exit 0
fi
exec "$REAL_TMUX" -L "$TEST_SOCKET" -f "$TEST_CONF" "\$@"
EOF
chmod +x "$FAKE_DIR/tmux"

PATH="$FAKE_DIR:$PATH" bash "$TEST_ROOT/scripts/cleanup.sh"

# Stale key should still be present because cleanup must have bailed out.
out=$(_tmux show-environment -g 'TMUX_CLAUDE_SIGNAL_%11_STATE' 2>&1)
case "$out" in
  "TMUX_CLAUDE_SIGNAL_%11_STATE=done") ;;
  *) printf '  FAIL [safety: stale key removed despite empty list-windows]\n    actual: %s\n' "$out" >&2; _failures=$((_failures + 1)) ;;
esac

report
