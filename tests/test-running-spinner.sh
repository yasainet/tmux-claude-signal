#!/usr/bin/env bash
# spinner.sh returns a padded frame from @claude-signal-running-frames.

set -euo pipefail
source "$(dirname "$0")/lib/test-lib.sh"

setup_tmux
trap teardown_tmux EXIT

echo "  case: frames unset → empty output"
out=$(TMUX_SOCKET="$TEST_SOCKET" bash "$TEST_ROOT/scripts/spinner.sh")
assert_empty "$out" "no frames means no output"

echo "  case: frames set → output is one space + frame + one space"
_tmux set-option -g "@claude-signal-running-frames" "A B C D"
out=$(TMUX_SOCKET="$TEST_SOCKET" bash "$TEST_ROOT/scripts/spinner.sh")
case "$out" in
  " A "|" B "|" C "|" D ") ;;
  *) printf '  FAIL [unexpected output: %q]\n' "$out" >&2; _failures=$((_failures + 1)) ;;
esac

echo "  case: index = epoch_sec mod len"
# Mock date by injecting a stub on PATH. Test that index calculation works.
FAKE_DIR="$(mktemp -d -t claude-signal-spinner-XXXXXX)"
trap 'teardown_tmux; rm -rf "$FAKE_DIR"' EXIT
cat > "$FAKE_DIR/date" <<'EOF'
#!/usr/bin/env bash
echo 7
EOF
chmod +x "$FAKE_DIR/date"
# 7 mod 4 = 3 → "D"
out=$(PATH="$FAKE_DIR:$PATH" TMUX_SOCKET="$TEST_SOCKET" bash "$TEST_ROOT/scripts/spinner.sh")
assert_eq " D " "$out" "epoch 7 mod 4 → D"

report
