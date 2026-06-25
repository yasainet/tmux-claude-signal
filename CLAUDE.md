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
- Theme は global level (`set -g window-status-style ...`) で設定する前提。
  - 上書きは window option レベルのみ。off / focus で window option を unset すれば global default に戻る。
  - window option レベルの theme はサポート外 (env-less restore 採用、`docs/DECISIONS.md` の 2026-06-25 env-less)。
- running / needs-input / done すべて bg 軸 (window-status-style) で表現する。
  - running は default `#9ece6a` (tokyonight green) で focus 永続 (`STATE=running` セット)。
  - needs-input / done は focus でクリアされる (unread mark)。
  - focus-ack は STATE=running なら window option unset を skip。
  - 旧 spinner.sh / `#()` 軸は tmux 3.6 で format job 評価が不安定だったため廃止 (`docs/DECISIONS.md` の 2026-06-25 spinner 廃止)。
- env は `STATE` のみ。plugin source 時に古い `ORIG_*` 残骸も含めて cleanup される (`scripts/cleanup.sh`)。
- debug log は `@claude-signal-debug 1` で opt-in、デフォルト無音。
  出力先は `${TMUX_CLAUDE_SIGNAL_LOG:-/tmp/claude-signal.log}`。
  `scripts/log.sh` の `sig_log` / `sig_log_enabled` を `state.sh` と `focus-ack.sh` が source する。

## Commands

- `bash tests/run-all.sh` runs the full test suite in detached tmux servers.
- `bash scripts/state.sh --state <running|needs-input|done|off>` drives state transition manually.

## Verification

- `bash tests/run-all.sh` must pass after any change to `scripts/` or `tmux-claude-signal.tmux`.
- Manual smoke: start a tmux session, source `tmux-claude-signal.tmux`, drive states via `scripts/state.sh`, observe window-status color.

## Glossaries

- running: Claude Code が tool を実行中 (PreToolUse 発火後)。bg 色 (default green) で focus 永続。
- needs-input: Claude Code is blocked on a permission prompt waiting for the user. Color clears on focus.
- done: Claude Code's Stop hook fired (turn finished). Color persists until window focus to act as unread mark.
- off: clear any signal and restore the original window-status style. Used on resume (UserPromptSubmit / PreToolUse).
