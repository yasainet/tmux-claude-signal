#!/usr/bin/env bash
# A global window-status-style (theme) is restored by clearing the window
# option layer. Plugin only touches window option; theme survives at global.

set -euo pipefail
source "$(dirname "$0")/lib/test-lib.sh"

setup_tmux
trap teardown_tmux EXIT

_tmux new-window -t test
window_id=$(_tmux display-message -p -t test:2 '#{window_id}')
pane_id=$(_tmux display-message -p -t "$window_id" '#{pane_id}')
_tmux select-window -t test:1

theme_style="bg=#16161e,fg=#a9b1d6"
_tmux set-option -g window-status-style "$theme_style"

assert_evaluated_style() {
  local expected="$1" msg="$2"
  assert_eq "$expected" "$(_tmux display-message -p -t "$window_id" "#{E:window-status-style}")" "$msg"
}

echo "  case: theme style is the evaluated baseline"
assert_empty "$(get_style "$window_id")" "no window-level override"
assert_evaluated_style "$theme_style" "theme baseline evaluated"

echo "  case: needs-input overrides theme"
state_sh "$pane_id" --state needs-input
assert_eq "bg=yellow,fg=black" "$(get_style "$window_id")" "needs-input override at window level"
assert_evaluated_style "bg=yellow,fg=black" "needs-input override evaluated"

echo "  case: off restores theme (window option cleared)"
state_sh "$pane_id" --state off
assert_empty "$(get_style "$window_id")" "off clears window-level override"
assert_evaluated_style "$theme_style" "theme restored evaluated"

echo "  case: done overrides, focus restores theme"
state_sh "$pane_id" --state done
assert_eq "bg=red,fg=black" "$(get_style "$window_id")" "done override"
_tmux select-window -t "$window_id"
focus_ack_sh "$pane_id" "$window_id"
assert_empty "$(get_style "$window_id")" "focus clears window-level override"
assert_evaluated_style "$theme_style" "theme restored after focus"

echo "  case: theme restored after running → off"
_tmux select-window -t test:1
state_sh "$pane_id" --state running
assert_eq "bg=#9ece6a,fg=#15161e" "$(get_style "$window_id")" "running override"
state_sh "$pane_id" --state off
assert_empty "$(get_style "$window_id")" "off clears window-level override"
assert_evaluated_style "$theme_style" "theme restored after off"

report
