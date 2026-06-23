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

- Claude Code has no hook for "permission granted" or "tool resumed".
  - UserPromptSubmit is treated as two-stage (off then running) so stale needs-input clears on next prompt.
- `pane-focus-in` does not fire reliably for panes running Claude Code TUI.
  - Focus handler is registered on three hooks (pane-focus-in, after-select-window, after-select-pane) and self-checks active pane to drop stale invocations.
- Theme-provided `window-status-style` must survive plugin state.
  - Original value is saved under `__UNSET__` sentinel before overwrite and restored on clear.
- Running color must be distinguishable from "done acknowledged then idle".
  - Running color is opt-in via `@claude-signal-running-bg` / `-fg`.
  - When configured, focus-ack does NOT clear it (only needs-input and done are treated as attention signals that clear on view).

## Commands

- `bash tests/run-all.sh` runs the full test suite in detached tmux servers.
- `bash scripts/state.sh --state <running|needs-input|done|off>` drives a state transition manually.

## Verification

- `bash tests/run-all.sh` must pass after any change to `scripts/` or `tmux-claude-signal.tmux`.
- Manual smoke: start a tmux session, source `tmux-claude-signal.tmux`, drive states via `scripts/state.sh`, observe window-status color.

## Glossaries

- running: Claude Code is processing a prompt or tool call. Color is opt-in and persists across focus.
- needs-input: Claude Code is blocked on a permission prompt waiting for the user. Color clears on focus.
- done: Claude Code's Stop hook fired (turn finished). Color persists until window focus to act as unread mark.
