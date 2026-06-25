# Decisions

不可逆な技術選定と包括判断のみを 1 行で残す。
詳細は spec / commit / コードを参照する。

## 2026-06-25 running spinner

- running は window-status-format 軸のスピナーで表現する。
- 過去削除した bg 色は再採用しない。
- 有効化は `@claude-signal-running-frames` の opt-in。
- 詳細は `docs/superpowers/specs/2026-06-25-running-spinner-design.md`。

## 2026-06-25 spinner 廃止 → running も bg 色化

- 上記スピナー方針を撤回し、running も bg 軸 (window-status-style) で表現する。
- 理由: tmux 3.6 の `#()` format job 評価が現実環境で不安定で、status-interval / job キャッシュ / theme との衝突が再現した。`#()` を一切使わない設計に倒す。
- default は `@claude-signal-running-bg=#9ece6a` (tokyonight green) / `@claude-signal-running-fg=#15161e`、override 可。
- focus 永続 (STATE=running セット) は維持。focus-ack の skip ロジックも維持。
- `scripts/spinner.sh`, `@claude-signal-running-frames`, `wrap_format` / `restore_format` を削除。

## 2026-06-25 env-less restore (ORIG_* 廃止)

- `TMUX_CLAUDE_SIGNAL_@N_ORIG_STYLE` / `_ORIG_CURRENT` の保存と復元を廃止し、`STATE` env のみ残す。
- 理由: 並列発火する hook (PreToolUse / UserPromptSubmit の race) と、cleanup で env だけ消えて window option が残ったセッション再開で、ORIG に「plugin が apply した中間状態の色」が保存されるバグが発生した (debug log の 2026-06-25 22:21:15 で `RESTORE_WRITE value=bg=#9ece6a,fg=#15161e` を観測)。
- 新挙動: `apply_style` = window option set / `clear_style` = window option unset / focus-ack の restore = window option unset。
- theme は global level (`set -g window-status-style ...`) で設定する前提。window option を unset すれば global default に戻る。window option レベルの theme はサポート外。
- 副次: hook の並列実行に対しても idempotent (最後の apply が勝つ、race で stale が残らない)。
