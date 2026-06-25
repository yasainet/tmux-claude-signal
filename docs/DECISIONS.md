# Decisions

不可逆な技術選定と包括判断のみを 1 行で残す。
詳細は spec / commit / コードを参照する。

## 2026-06-26 running 廃止

- running 状態の表示そのものを廃止する。signal は needs-input / done / off の 3 状態のみ。
- 理由: 「Claude が動いている」可視化は色が常時点灯することで意識を散漫にし、本来の unread mark として効くべき needs-input / done のシグナル強度を相対的に下げていた。
- PreToolUse hook は running 発火をやめ、`--state off` にマッピングし直す (resume 時に stale needs-input / done を消す本来の役割に戻す)。
- `STATE` env と focus-ack の skip ロジックは不要になり削除。`cleanup.sh` は過去 plugin の残骸 (`@N_STATE`, `@N_ORIG_*`, `%`) を一掃する保険として残す。
- 副次効果: PreToolUse → focus-ack の race で done が再表示される既知バグも、STATE env と running 軸の撤廃で同時に解消される (`memory/unread-revival-investigation` 終了)。

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

## 2026-06-26 scope を cross-session state marker 公開に拡張

- scope を「同 session 内の着色対象 + 全 session の state marker 公開」に拡張する。
- 理由: 複数 session 環境での claude 状態把握 UX の改善。着色対象は同 session 内 window で不変。state marker の公開は純粋に API surface 追加で scope boundary は汚さない。
- `@claude-signal-state` window option として state を公開し、集約スクリプト `cross-session.sh` が全 session window を参照可能にする。

## 2026-06-26 state marker を `@claude-signal-state` window option で公開

- state marker を window option `@claude-signal-state` として公開し、値は needs-input / done / (unset) とする。
- 理由: read-only なメタデータを global window option 層で提供し、集約スクリプトおよび将来の外部監視ツールが参照可能にする。
- state.sh の apply_style / clear_style と focus-ack.sh でこの option を set / unset する。

## 2026-06-26 cross-session indicator の記号は `●` 単一

- cross-session indicator の記号は `●` (Unicode U+25CF) 単一とし、色 (黄 = needs-input、赤 = done) で状態を区別し、件数は出さない。
- 理由: Nerd Font 非依存で SSH 先 fallback を担保し、複数 state の同一性で視認性と情報量のバランスを取る。
- needs-input = fg=yellow、done = fg=red のシンプルな色 map で、複数状態が並ぶ場合は needs-input (黄) → done (赤) の順。
