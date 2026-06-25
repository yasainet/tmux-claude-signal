# Stale TMUX_CLAUDE_SIGNAL env cleanup on plugin source

## 背景

tmux server を長期稼働させると `TMUX_CLAUDE_SIGNAL_*` キーが増え続ける。
開発機実測では約 1 ヶ月で 36 キー溜まった。
意味があるのは `TMUX_CLAUDE_SIGNAL_DIR` 1 個のみで残り 35 個は残骸だった。

残骸の内訳は 2 種類。

旧スキーマ: `TMUX_CLAUDE_SIGNAL_%N_STATE` / `TMUX_CLAUDE_SIGNAL_%N_PENDING`。
refactor 2722863 で削除済みのキーで、現コードは参照しない。

不在 window 由来: `TMUX_CLAUDE_SIGNAL_@N_ORIG_STYLE` / `..._ORIG_CURRENT`。
`apply_style` 後に `focus-ack.sh` を経ず window が close された残骸。
tmux の window ID は close 後に再利用されないため現コードからは参照されない。

いずれも無害だが `show-environment -g` の肥大化を招きノイズになる。
将来のスキーマ変更時にも混乱要因となる。

## ゴール

plugin が source される時に明らかに不要なキーを `set-environment -gu` で消す。

## 非ゴール

既存スクリプトのロジック変更はしない。
復活バグ調査は別問題として継続中で、本 spec のスコープ外とする。
周期実行 (hook 経由 / タイマー) は YAGNI として入れない。

## 設計

### アーキテクチャ

新規ファイル `scripts/cleanup.sh` を追加して単体テスト可能にする。
`tmux-claude-signal.tmux` の末尾から `tmux run-shell` で呼び出す。
既存の `state.sh` / `focus-ack.sh` / `tmux-claude-signal.tmux` のロジックは無変更。
既存テスト 3 本 (state-transitions / focus-ack / theme-preservation) も無変更。

### 掃除ロジック

擬似コード:

```
existing = list-windows -a で得た window_id の集合
if existing が空: exit 0  # 安全装置

for each key in show-environment -g の TMUX_CLAUDE_SIGNAL_* 行:
  TMUX_CLAUDE_SIGNAL_DIR              → keep
  TMUX_CLAUDE_SIGNAL_%*               → unset (旧スキーマ)
  TMUX_CLAUDE_SIGNAL_@N_ORIG_*:
    N in existing                     → keep
    N not in existing                 → unset
  上記いずれにもマッチしない不明キー  → keep (将来スキーマ用)
```

### 安全装置

`tmux list-windows -a` が空文字列を返したら何もせず exit 0 する。
tmux 異常時に現存 ORIG を巻き込み削除するのを防ぐ意図。

`tmux set-environment -gu` は `|| true` で握る (既消えでも良い)。
`command -v tmux` が失敗したら exit 0。
スクリプトは `set -euo pipefail` を使うが tmux 系コマンドの失敗は個別吸収する。

### 設定

なし。デフォルト ON、opt-out オプションは入れない。
理由: 掃除対象は現コード未参照のキーか tmux 仕様上再利用されない window ID のキーのみ。
論理的に現存 signal を壊しようがなく設定で無効化する動機がない。

### テスト

新規 `tests/test-cleanup.sh` を追加する。
既存の `tests/lib/test-lib.sh` ヘルパーを利用し `tests/run-all.sh` から呼ぶ。

ケース 1: 通常掃除

- [ ] pre-set: 旧スキーマ `%11_STATE` / `%11_PENDING`、不在 window 用 `@999_ORIG_STYLE`、現存 window 用 `@<live>_ORIG_STYLE`、`TMUX_CLAUDE_SIGNAL_DIR`
- [ ] run: `cleanup.sh`
- [ ] assert: 旧スキーマ 2 件と不在 window 用が消えた
- [ ] assert: 現存 window 用と `TMUX_CLAUDE_SIGNAL_DIR` は残った

ケース 2: 安全装置 (list-windows 空)

- [ ] pre-set: ケース 1 と同じ env
- [ ] run: window が 1 つもない状態で `cleanup.sh`
- [ ] assert: env は変化なし

ケース 3: 未知キーの保護

- [ ] pre-set: `TMUX_CLAUDE_SIGNAL_FUTURE_FOO=bar`
- [ ] run: `cleanup.sh`
- [ ] assert: 残っている

### ドキュメント

`README.md` インストール手順に「過去スキーマと不在 window 由来の env は plugin source 時に自動掃除される」を 1 行追記する。
`CLAUDE.md` Constraints に「env は plugin source 時に cleanup される (`scripts/cleanup.sh`)」を 1 行追記する。

## 検証

`bash tests/run-all.sh` が新規 test-cleanup を含めて全 pass する。
開発機で `tmux source ~/.tmux.conf` (TPM 経由 reload) を走らせる。
`tmux show-environment -g | grep TMUX_CLAUDE_SIGNAL` が `TMUX_CLAUDE_SIGNAL_DIR` と現存 window 用 ORIG のみ残ることを目視確認する。
