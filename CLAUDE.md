# CLAUDE.md

Window-status color signal for Claude Code panes inside the current tmux session.

## Summary

- Claude Code hooks (UserPromptSubmit / PermissionRequest / Stop) drive per-window color state.
- Color clears as soon as the user focuses the window so the signal acts as an unread mark.
- Scope is intentionally narrow (single session, single agent, window-status only).

## Environments

- Local tmux only.
- No CI, no preview, no production deploy target.

## Constraints

- Claude Code has no hook for "permission granted".
  - PreToolUse (matcher empty = all tools) fires after permission resolution, just before the tool runs.
  - Mapping PreToolUse to off clears stale needs-input as soon as Claude resumes work.
  - UserPromptSubmit also maps to off so a new prompt clears any stale signal.
- `pane-focus-in` does not fire reliably for panes running Claude Code TUI.
  - Focus handler is registered on three hooks (pane-focus-in, after-select-window, after-select-pane) and self-checks active pane to drop stale invocations.
- Theme-provided `window-status-style` must survive plugin state.
  - Original value is saved under `__UNSET__` sentinel before overwrite and restored on clear.
- needs-input / done は bg 軸 (window-status-style) で表現し focus でクリア。
  - running は format 軸 (window-status-format) で別管理し focus 永続。
  - focus-ack は STATE=running なら restore を skip。
  - spinner.sh は tmux `#()` から 1 秒粒度で呼ぶ stateless スクリプト。
  - frames は `@claude-signal-running-frames` にスペース区切りで設定。
- env は plugin source 時に cleanup される (`scripts/cleanup.sh`)。

## Commands

- `bash tests/run-all.sh` runs the full test suite in detached tmux servers.
- `bash scripts/state.sh --state <running|needs-input|done|off>` drives state transition manually.

## Verification

- `bash tests/run-all.sh` must pass after any change to `scripts/` or `tmux-claude-signal.tmux`.
- Manual smoke: start a tmux session, source `tmux-claude-signal.tmux`, drive states via `scripts/state.sh`, observe window-status color.

## Glossaries

- running: Claude Code が tool を実行中 (PreToolUse 発火後)。
  `@claude-signal-running-frames` 設定時のみスピナーを表示。focus 永続。
- needs-input: Claude Code is blocked on a permission prompt waiting for the user. Color clears on focus.
- done: Claude Code's Stop hook fired (turn finished). Color persists until window focus to act as unread mark.
- off: clear any signal and restore the original window-status style. Used on resume (UserPromptSubmit / PreToolUse).
