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
- Only attention signals are colored (needs-input, done); both clear on focus.
  - A "running" color was dropped after use showed it added noise without value.
  - focus-ack just restores the saved original, so it needs no per-state tracking.

## Commands

- `bash tests/run-all.sh` runs the full test suite in detached tmux servers.
- `bash scripts/state.sh --state <needs-input|done|off>` drives a state transition manually.

## Verification

- `bash tests/run-all.sh` must pass after any change to `scripts/` or `tmux-claude-signal.tmux`.
- Manual smoke: start a tmux session, source `tmux-claude-signal.tmux`, drive states via `scripts/state.sh`, observe window-status color.

## Glossaries

- needs-input: Claude Code is blocked on a permission prompt waiting for the user. Color clears on focus.
- done: Claude Code's Stop hook fired (turn finished). Color persists until window focus to act as unread mark.
- off: clear any signal and restore the original window-status style. Used on resume (UserPromptSubmit / PreToolUse).
