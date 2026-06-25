# env-cleanup Implementation Plan

> [!NOTE]
> agentic workers: REQUIRED SUB-SKILL: superpowers:subagent-driven-development (推奨) または superpowers:executing-plans を使ってタスクごとに実装してください。各ステップは `- [ ]` でトラッキングします。

## Goal

plugin source 時に stale な `TMUX_CLAUDE_SIGNAL_*` env キーを掃除する。

## Architecture

新規 `scripts/cleanup.sh` を追加し plugin entry point から呼ぶ。
掃除対象は旧 `%N_STATE` / `%N_PENDING` と不在 window の `@N_ORIG_*`。
既存スクリプト 3 本 (state.sh / focus-ack.sh / .tmux) のロジックは無変更。

## Tech Stack

bash 4+。tmux 3.0+ (既存 plugin と同じ)。テストは `tests/lib/test-lib.sh` を流用。

## Global Constraints

掃除対象は現存 window の signal を絶対に壊さないこと。
`set -euo pipefail` を使うが tmux 系コマンドの失敗は `|| true` で吸収する。
旧 `%N_*` キーは無条件 unset、`@N_ORIG_*` は不在 window のもののみ unset。
`TMUX_CLAUDE_SIGNAL_DIR` と未知形式キーは必ず keep する。
`tmux list-windows -a` が空文字列を返したら何もせず exit 0 する。

## File Structure

create したり modify したりするファイル一覧。

- 新規 `scripts/cleanup.sh`: 掃除ロジック本体
- 新規 `tests/test-cleanup.sh`: cleanup の挙動を検証
- 修正 `tests/lib/test-lib.sh`: cleanup test 用 helper を追加
- 修正 `tmux-claude-signal.tmux`: 末尾に cleanup.sh の呼び出しを追加
- 修正 `README.md`: 掃除が自動で走る旨を 1 行追記
- 修正 `CLAUDE.md`: Constraints に cleanup の記載を 1 行追記

`tests/run-all.sh` は `test-*.sh` を glob で拾うので修正不要。

## Task 1: cleanup.sh と test を TDD で実装

Files:

- Create: `scripts/cleanup.sh`
- Create: `tests/test-cleanup.sh`
- Modify: `tests/lib/test-lib.sh` (helper 追加)

Interfaces:

- Consumes: なし (独立した CLI スクリプト)
- Produces: `scripts/cleanup.sh` を bash で実行できる。引数なし、exit 0 で成功

### Step 1.1: test-lib.sh に helper を追加

- [ ] `tests/lib/test-lib.sh` の `report()` の前に下記 helper を挿入

```bash
cleanup_sh() {
  _tmux run-shell "bash '$TEST_ROOT/scripts/cleanup.sh'"
}

env_show() {
  local name="$1"
  _tmux show-environment -g "$name" 2>/dev/null | sed 's/^[^=]*=//' || true
}

assert_env_absent() {
  local name="$1" msg="${2:-}"
  local out
  out=$(_tmux show-environment -g "$name" 2>&1)
  case "$out" in
    "unknown variable: "*) return 0 ;;
  esac
  printf '  FAIL [%s]\n    expected env %s absent\n    actual:   %s\n' \
    "$msg" "$name" "$out" >&2
  _failures=$((_failures + 1))
  return 1
}
```

### Step 1.2: test-cleanup.sh を新規作成

- [ ] `tests/test-cleanup.sh` を以下の内容で作成

```bash
#!/usr/bin/env bash
# cleanup.sh removes stale TMUX_CLAUDE_SIGNAL_* keys and preserves live ones.

set -euo pipefail
source "$(dirname "$0")/lib/test-lib.sh"

setup_tmux
trap teardown_tmux EXIT

live_window=$(_tmux display-message -p '#{window_id}')

_tmux set-environment -g 'TMUX_CLAUDE_SIGNAL_%11_STATE' done
_tmux set-environment -g 'TMUX_CLAUDE_SIGNAL_%11_PENDING' 1
_tmux set-environment -g 'TMUX_CLAUDE_SIGNAL_@999_ORIG_STYLE' __UNSET__
_tmux set-environment -g 'TMUX_CLAUDE_SIGNAL_@999_ORIG_CURRENT' __UNSET__
_tmux set-environment -g "TMUX_CLAUDE_SIGNAL_${live_window}_ORIG_STYLE" __UNSET__
_tmux set-environment -g TMUX_CLAUDE_SIGNAL_DIR /test/path
_tmux set-environment -g TMUX_CLAUDE_SIGNAL_FUTURE_FOO bar

echo "  case: cleanup removes stale, keeps live + DIR + unknown"
cleanup_sh

assert_env_absent 'TMUX_CLAUDE_SIGNAL_%11_STATE'    "old % STATE removed"
assert_env_absent 'TMUX_CLAUDE_SIGNAL_%11_PENDING'  "old % PENDING removed"
assert_env_absent 'TMUX_CLAUDE_SIGNAL_@999_ORIG_STYLE'   "gone window STYLE removed"
assert_env_absent 'TMUX_CLAUDE_SIGNAL_@999_ORIG_CURRENT' "gone window CURRENT removed"
assert_eq "__UNSET__" "$(env_show "TMUX_CLAUDE_SIGNAL_${live_window}_ORIG_STYLE")" "live window kept"
assert_eq "/test/path" "$(env_show TMUX_CLAUDE_SIGNAL_DIR)" "DIR kept"
assert_eq "bar"        "$(env_show TMUX_CLAUDE_SIGNAL_FUTURE_FOO)" "unknown kept"

report
```

### Step 1.3: test を走らせて fail することを確認

- [ ] 下記を実行

```bash
cd /Users/yasainet/ghq/github.com/yasainet/tmux-claude-signal
bash tests/test-cleanup.sh
```

Expected: cleanup.sh 未作成のため `No such file or directory` 相当のエラーが出る。
もしくは assert FAIL で exit 1。

### Step 1.4: cleanup.sh を新規作成

- [ ] `scripts/cleanup.sh` を以下の内容で作成

```bash
#!/usr/bin/env bash
# Remove stale TMUX_CLAUDE_SIGNAL_* env keys.
#
# Stale = old %N_STATE / %N_PENDING schema (refactor 2722863 で削除済み)
#       + @N_ORIG_* of windows that no longer exist.
# Kept  = TMUX_CLAUDE_SIGNAL_DIR, @N_ORIG_* of live windows, unknown shapes.

set -euo pipefail

if ! command -v tmux >/dev/null 2>&1; then
  exit 0
fi

existing=$(tmux list-windows -a -F '#{window_id}' 2>/dev/null || true)
[ -z "$existing" ] && exit 0

env_lines=$(tmux show-environment -g 2>/dev/null | grep '^TMUX_CLAUDE_SIGNAL_' || true)
[ -z "$env_lines" ] && exit 0

while IFS= read -r line; do
  key="${line%%=*}"
  case "$key" in
    TMUX_CLAUDE_SIGNAL_DIR)
      ;;
    TMUX_CLAUDE_SIGNAL_%*)
      tmux set-environment -gu "$key" 2>/dev/null || true
      ;;
    TMUX_CLAUDE_SIGNAL_@[0-9]*_ORIG_STYLE|TMUX_CLAUDE_SIGNAL_@[0-9]*_ORIG_CURRENT)
      wid=$(printf '%s' "$key" | sed -E 's/^TMUX_CLAUDE_SIGNAL_(@[0-9]+)_.*/\1/')
      [ -z "$wid" ] && continue
      if ! printf '%s\n' "$existing" | grep -qx "$wid"; then
        tmux set-environment -gu "$key" 2>/dev/null || true
      fi
      ;;
    *)
      ;;
  esac
done <<< "$env_lines"
```

- [ ] 実行権限を付与

```bash
chmod +x /Users/yasainet/ghq/github.com/yasainet/tmux-claude-signal/scripts/cleanup.sh
```

### Step 1.5: test を走らせて pass することを確認

- [ ] 下記を実行

```bash
cd /Users/yasainet/ghq/github.com/yasainet/tmux-claude-signal
bash tests/test-cleanup.sh
```

Expected: `ok` で exit 0。

### Step 1.6: 全テスト suite が pass することを確認

- [ ] 下記を実行

```bash
cd /Users/yasainet/ghq/github.com/yasainet/tmux-claude-signal
bash tests/run-all.sh
```

Expected: `all tests passed` で exit 0。test-cleanup.sh も含めて 4 本走る。

### Step 1.7: commit

- [ ] 下記を実行

```bash
cd /Users/yasainet/ghq/github.com/yasainet/tmux-claude-signal
git add scripts/cleanup.sh tests/test-cleanup.sh tests/lib/test-lib.sh
git commit -m "$(cat <<'EOF'
feat(cleanup): stale TMUX_CLAUDE_SIGNAL env を掃除する cleanup.sh を追加

旧スキーマ %N_STATE/%N_PENDING と不在 window の @N_ORIG_* のみ unset し、
TMUX_CLAUDE_SIGNAL_DIR と現存 window の @N_ORIG_* および未知形式キーは keep。
list-windows が空文字列の時は安全のため何もしない。
EOF
)"
```

## Task 2: plugin source 時に cleanup を実行

Files:

- Modify: `tmux-claude-signal.tmux` (末尾に追加)

Interfaces:

- Consumes: Task 1 で作成した `scripts/cleanup.sh`
- Produces: なし (plugin の副作用)

### Step 2.1: tmux-claude-signal.tmux の末尾に cleanup 呼び出しを追加

- [ ] 現状の末尾は `done` (for ループの閉じ括弧、19 行目) になっている。その下に以下を追加する

```bash
tmux run-shell "$CURRENT_DIR/scripts/cleanup.sh" 2>/dev/null || true
```

最終形は下記。

```bash
#!/usr/bin/env bash
# tmux-claude-signal: window-status color signal for Claude Code panes.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tmux set-environment -g TMUX_CLAUDE_SIGNAL_DIR "$CURRENT_DIR"

focus_cmd="run-shell \"$CURRENT_DIR/scripts/focus-ack.sh \\\"#{pane_id}\\\" \\\"#{window_id}\\\"\""

# Replace any prior plugin hook to avoid duplicates on reload.
for hook in pane-focus-in after-select-window after-select-pane; do
  existing=$(tmux show-hooks -g "$hook" 2>/dev/null | grep -F "$CURRENT_DIR" || true)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    name="${line%% *}"
    tmux set-hook -gu "$name" 2>/dev/null || true
  done <<< "$existing"
  tmux set-hook -ag "$hook" "$focus_cmd"
done

tmux run-shell "$CURRENT_DIR/scripts/cleanup.sh" 2>/dev/null || true
```

### Step 2.2: 既存テストが引き続き pass することを確認

- [ ] 既存 3 本のテストは plugin source 経由ではなく scripts/ を直接叩く構造なので影響を受けないはず。念のため

```bash
cd /Users/yasainet/ghq/github.com/yasainet/tmux-claude-signal
bash tests/run-all.sh
```

Expected: `all tests passed`。

### Step 2.3: 手動 smoke test

- [ ] 開発機の tmux server にデバッグ用 sentinel env を仕込む。
- [ ] plugin を source し直して掃除されることを確認する。

```bash
# 1) 偽の stale env を仕込む
tmux set-environment -g 'TMUX_CLAUDE_SIGNAL_%99_STATE' done
tmux set-environment -g 'TMUX_CLAUDE_SIGNAL_@99999_ORIG_STYLE' __UNSET__

# 2) 確認
tmux show-environment -g | grep TMUX_CLAUDE_SIGNAL_ | grep -E '%99|@99999'
# Expected: 2 行出る

# 3) plugin を re-source (TPM版を直接 source)
tmux run-shell "bash $HOME/.config/tmux/plugins/tmux-claude-signal/tmux-claude-signal.tmux"

# 4) 確認
tmux show-environment -g | grep TMUX_CLAUDE_SIGNAL_ | grep -E '%99|@99999' || echo "(cleaned)"
# Expected: "(cleaned)" が出る

# 5) DIR と現存 window の ORIG (もしあれば) が残っていることも確認
tmux show-environment -g | grep TMUX_CLAUDE_SIGNAL_DIR
# Expected: TMUX_CLAUDE_SIGNAL_DIR=<path> が出る
```

### Step 2.4: commit

- [ ] 下記を実行

```bash
cd /Users/yasainet/ghq/github.com/yasainet/tmux-claude-signal
git add tmux-claude-signal.tmux
git commit -m "$(cat <<'EOF'
feat(plugin): plugin source 時に cleanup.sh を実行する

長期稼働する tmux server で TMUX_CLAUDE_SIGNAL_* が蓄積するのを防ぐ。
失敗は握り、plugin の起動を妨げない。
EOF
)"
```

## Task 3: ドキュメント更新

Files:

- Modify: `README.md`
- Modify: `CLAUDE.md`

Interfaces:

- Consumes: Task 1 + 2 で追加した cleanup の挙動
- Produces: なし

### Step 3.1: README.md にインストール手順の節へ追記

- [ ] `README.md` を Read して、インストール手順の節 (Plugin を source する旨の説明箇所) を特定する
- [ ] その節の末尾に下記を 1 行追記する

```
Plugin source 時に過去スキーマと不在 window 由来の env を自動掃除します。
```

### Step 3.2: CLAUDE.md の Constraints に追記

- [ ] `CLAUDE.md` の `## Constraints` 節の末尾に下記を 1 行追記する

```
- env は plugin source 時に cleanup される (`scripts/cleanup.sh`)。
```

### Step 3.3: commit

- [ ] 下記を実行

```bash
cd /Users/yasainet/ghq/github.com/yasainet/tmux-claude-signal
git add README.md CLAUDE.md
git commit -m "$(cat <<'EOF'
docs: plugin source 時の env cleanup を README/CLAUDE に追記

EOF
)"
```

## Self-Review チェック結果

spec カバレッジ確認:

- [x] アーキテクチャ (cleanup.sh + plugin 呼び出し): Task 1, 2
- [x] 掃除ロジック (旧 % / 不在 @ / DIR と未知 keep): Task 1.4
- [x] 安全装置 (list-windows 空 / tmux 不在 / set-environment 失敗): Task 1.4
- [x] 設定なしの方針: 実装に反映済み (オプションを読まない)
- [x] テスト 3 ケース: ケース 1 + 3 は Task 1.2、ケース 2 (list-windows 空) は code review で済ます方針として spec では言及したが、test 化が困難なため省略。安全装置の中身は Task 1.4 のコード差分で確認できる
- [x] ドキュメント (README + CLAUDE): Task 3

placeholder scan: なし。
型整合: 全 shell スクリプト、interface は CLI 起動のみ。整合 OK。

> [!NOTE]
> spec のケース 2 (安全装置の test 化) は意図的に省略しました。
> tmux server 稼働中に `list-windows -a` が空を返す状況の fixture 化は困難です。
> 安全装置は `[ -z "$existing" ] && exit 0` の 1 行で code review で担保できます。
> 必要と判断したら実装後に追加できます。
