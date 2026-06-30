# CLAUDE.md

Window-status color signal for Claude Code panes inside the current tmux session.

## Summary

- Claude Code hooks (UserPromptSubmit / PreToolUse / PermissionRequest / Stop) drive per-window color state.
- Color clears as soon as the user focuses the window so the signal acts as an unread mark.
- 着色対象は同 session 内 window のみで scope を絞る。
- state marker (`@claude-signal-state` window option) を公開し、`scripts/cross-session.sh` が全 session を集約して status-right に表示する。

## Environments

- Local tmux only.
- No CI, no preview, no production deploy target.

## Constraints

- 状態は needs-input / done / off の 3 つのみ。
  - running は集中阻害になるため廃止。
  - PreToolUse は running ではなく off にマッピングし、resume 時の stale 消しに利用する。
- Claude Code has no hook for "permission granted".
  - PreToolUse (matcher empty = all tools) fires after permission resolution, just before the tool runs.
  - Mapping PreToolUse to off clears stale needs-input as soon as Claude resumes work.
  - UserPromptSubmit も同様に off にマッピングし、新規プロンプトで stale を消す。
- SessionEnd hook で Claude 終了時に off を呼び、stale marker を残さない。
  - 異常終了 (SIGKILL 等) では発火しない可能性があるため、cross-session.sh 側で `@claude-signal-pane` の生存チェックを併用する。
- `pane-focus-in` does not fire reliably for panes running Claude Code TUI.
  - Focus handler is registered on three hooks (pane-focus-in, after-select-window, after-select-pane) and self-checks active pane to drop stale invocations.
- いま見ている pane への着色は state.sh 側で抑制する。
  - 見ている window で done/needs-input になっても focus は変化せず focus-ack が発火しない。
  - 抑制しないと離脱→復帰しないと既読にできない (after-select-window を人工的に起こす必要がある)。
  - 抑制条件は session_attached + window_active + pane_active で、focus-ack の clear 条件と対称。
  - detached session は「見ていない」ので着色し marker も残す。cross-session chip 点灯を維持するため。
- Theme は global level (`set -g window-status-style ...`) で設定する前提。
  - 上書きは window option レベルのみ。off / focus で window option を unset すれば global default に戻る。
  - window option レベルの theme はサポート外 (env-less restore 採用)。
- env は持たない。`cleanup.sh` は過去スキーマ (`%`, `@N_STATE`, `@N_ORIG_*`) の残骸を一掃する保険。
- debug log は `@claude-signal-debug 1` で opt-in、デフォルト無音。
  出力先は `${TMUX_CLAUDE_SIGNAL_LOG:-/tmp/claude-signal.log}`。
  `scripts/log.sh` の `sig_log` / `sig_log_enabled` を `state.sh` と `focus-ack.sh` が source する。

## Commands

- `bash tests/run-all.sh` runs the full test suite in detached tmux servers.
- `bash scripts/state.sh --state <needs-input|done|off>` drives state transition manually.

## Verification

- `bash tests/run-all.sh` must pass after any change to `scripts/` or `tmux-claude-signal.tmux`.
- Manual smoke: start a tmux session, source `tmux-claude-signal.tmux`, drive states via `scripts/state.sh`, observe window-status color.

## Glossaries

- needs-input: Claude Code is blocked on a permission prompt waiting for the user. Color clears on focus.
- done: Claude Code's Stop hook fired (turn finished). Color persists until window focus to act as unread mark.
- off: clear any signal and restore the original window-status style. Used on resume (UserPromptSubmit / PreToolUse).
- `@claude-signal-state`: window option として公開される state marker。値は `needs-input` / `done` / (unset)。`state.sh` の apply/clear と `focus-ack.sh` で同期され、`scripts/cross-session.sh` が全 window を集約して読む。
- `@claude-signal-pane`: marker を打った時点の Claude pane id。`cross-session.sh` で `tmux display-message -t <pane_id>` が空文字を返す (pane 消滅) なら stale として skip する。`@claude-signal-state` と必ずペアで apply/clear される。
