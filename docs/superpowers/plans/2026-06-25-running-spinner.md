# running Spinner Implementation Plan

> [!NOTE]
> agentic workers: REQUIRED SUB-SKILL: superpowers:subagent-driven-development
> (推奨) または superpowers:executing-plans を使ってタスクごとに実装してください。
> 各ステップは `- [ ]` でトラッキングします。

## Goal

running 状態を window-status タブの `#I` と `#W` の間に注入するスピナーで
表現する。bg と format の二軸分離、focus 永続、opt-in 設定で導入する。

## Architecture

`window-status-style` (bg/fg) は needs-input/done のみ上書き、
`window-status-format` は running のみ上書き (spinner 注入) する二軸分離。
window_id ベースの `STATE` env_key で focus-ack の skip を判定する。

## Tech Stack

bash 4+。tmux 3.0+ (既存 plugin と同じ)。
テストは `tests/lib/test-lib.sh` を流用、detached tmux server で走らせる。

## Global Constraints

`set -euo pipefail` を使うが tmux 系コマンドの失敗は `|| true` で吸収する。
opt-in: `@claude-signal-running-frames` 未設定で running hook が来てもゼロ影響。
needs-input/done/off は running と完全排他で、遷移時に format を必ず restore する。
focus-ack は STATE=running なら restore を skip する (focus 永続)。
spinner.sh は frames セットを space 区切りで受け、全 window 同期の epoch
位相でフレームを返す stateless スクリプトとする。

## File Structure

create / modify するファイル一覧:

- 新規 `scripts/spinner.sh` `#()` から呼ばれフレームを返す
- 修正 `scripts/state.sh` running case 追加 + format wrap 関数 inline
- 修正 `scripts/focus-ack.sh` STATE=running の skip 分岐を追加
- 修正 `scripts/cleanup.sh` `@N_STATE` / `@N_ORIG_FORMAT` パターン追加
- 修正 `hooks/claude-hooks.json` PreToolUse の off を running に変更
- 修正 `tests/lib/test-lib.sh` `get_format` / `spinner_sh` helper 追加
- 修正 `tests/test-state-transitions.sh` running 経路を追加
- 修正 `tests/test-focus-ack.sh` STATE=running 時の skip を追加
- 修正 `tests/test-theme-preservation.sh` running 後の theme 復元を追加
- 修正 `tests/test-cleanup.sh` `@N_STATE` / `@N_ORIG_FORMAT` 掃除を追加
- 新規 `tests/test-running-spinner.sh` spinner 出力と frames 設定の検証
- 新規 `tests/test-format-wrap.sh` `#I`/`#W` 検出と fallback の検証
- 修正 `README.md` opt-in 設定例
- 修正 `CLAUDE.md` glossary / constraints の更新

`tests/run-all.sh` は `test-*.sh` を glob で拾うため修正不要。

## Task 1: spinner.sh を TDD で実装

Files:

- Create: `scripts/spinner.sh`
- Create: `tests/test-running-spinner.sh`
- Modify: `tests/lib/test-lib.sh` (`spinner_sh` helper 追加)

Interfaces:

- Consumes: なし (独立した CLI スクリプト)
- Produces: `bash scripts/spinner.sh` が stdout にフレーム 1 文字を
  `' X '` (前後 1 スペース padding) で返す。frames 未設定なら空出力で exit 0

### Step 1.1: test-lib.sh に spinner_sh helper を追加

- [ ] `tests/lib/test-lib.sh` の `cleanup_sh()` の下に下記 helper を挿入

```bash
spinner_sh() {
  _tmux run-shell "bash '$TEST_ROOT/scripts/spinner.sh' > /tmp/claude-signal-spinner.out 2>&1"
  cat /tmp/claude-signal-spinner.out 2>/dev/null || true
}
```

### Step 1.2: failing test を書く

- [ ] `tests/test-running-spinner.sh` を作成

```bash
#!/usr/bin/env bash
# spinner.sh returns a padded frame from @claude-signal-running-frames.

set -euo pipefail
source "$(dirname "$0")/lib/test-lib.sh"

setup_tmux
trap teardown_tmux EXIT

echo "  case: frames unset → empty output"
out=$(bash "$TEST_ROOT/scripts/spinner.sh")
assert_empty "$out" "no frames means no output"

echo "  case: frames set → output is one space + frame + one space"
_tmux set-option -g "@claude-signal-running-frames" "A B C D"
out=$(bash "$TEST_ROOT/scripts/spinner.sh")
case "$out" in
  " A "|" B "|" C "|" D ") ;;
  *) printf '  FAIL [unexpected output: %q]\n' "$out" >&2; _failures=$((_failures + 1)) ;;
esac

echo "  case: index = epoch_sec mod len"
# Mock date by injecting a stub on PATH. Test that index calculation works.
FAKE_DIR="$(mktemp -d -t claude-signal-spinner-XXXXXX)"
trap 'teardown_tmux; rm -rf "$FAKE_DIR"' EXIT
cat > "$FAKE_DIR/date" <<'EOF'
#!/usr/bin/env bash
echo 7
EOF
chmod +x "$FAKE_DIR/date"
# 7 mod 4 = 3 → "D"
out=$(PATH="$FAKE_DIR:$PATH" bash "$TEST_ROOT/scripts/spinner.sh")
assert_eq " D " "$out" "epoch 7 mod 4 → D"

report
```

### Step 1.3: test を走らせて FAIL を確認

- [ ] 実行

```bash
bash tests/test-running-spinner.sh
```

期待: FAIL (`scripts/spinner.sh` が存在しないか空出力でない)

### Step 1.4: spinner.sh を実装

- [ ] `scripts/spinner.sh` を作成

```bash
#!/usr/bin/env bash
# Print the current spinner frame based on epoch seconds.
# Stateless: called from tmux #() and called fresh each evaluation.

set -euo pipefail

if ! command -v tmux >/dev/null 2>&1; then
  exit 0
fi

frames=$(tmux show-option -gqv "@claude-signal-running-frames" 2>/dev/null || true)
[ -z "$frames" ] && exit 0

IFS=' ' read -ra arr <<< "$frames"
[ "${#arr[@]}" -eq 0 ] && exit 0

i=$(( $(date +%s) % ${#arr[@]} ))
printf ' %s ' "${arr[$i]}"
```

### Step 1.5: 実行可能化と test PASS 確認

- [ ] 実行

```bash
chmod +x scripts/spinner.sh
bash tests/test-running-spinner.sh
```

期待: `ok`

### Step 1.6: 既存テストが回帰してないか確認

- [ ] 実行

```bash
bash tests/run-all.sh
```

期待: `all tests passed`

### Step 1.7: commit

- [ ] 実行

```bash
git add scripts/spinner.sh tests/test-running-spinner.sh tests/lib/test-lib.sh
git commit -m "feat(spinner): epoch 位相で動く stateless spinner.sh を追加"
```

## Task 2: state.sh に running case と format wrap 関数を inline

Files:

- Modify: `scripts/state.sh`
- Modify: `tests/test-state-transitions.sh`

Interfaces:

- Consumes: `scripts/spinner.sh` (`#()` 経由でパスを埋め込む)
- Produces:
  - `bash scripts/state.sh --state running --pane <pane>` が
    `@claude-signal-running-frames` 設定時に `window-status-format` を
    `#I#(...spinner.sh)#W` に wrap し、`TMUX_CLAUDE_SIGNAL_<window_id>_STATE`
    を `"running"` に set する
  - needs-input/done/off は STATE を unset し、format を restore する

### Step 2.1: failing test を書く

- [ ] `tests/test-state-transitions.sh` の `report` 直前に下記を追加

```bash
echo "  case: running without frames → no-op"
_tmux set-window-option -t "$window_id" window-status-format "#I:#W"
state_sh "$pane_id" --state running
assert_eq "#I:#W" "$(_tmux show-options -wqv -t "$window_id" window-status-format)" "format untouched without frames"
assert_env_absent "TMUX_CLAUDE_SIGNAL_${window_id}_STATE" "STATE not set without frames"

echo "  case: running with frames → format wrap and STATE set"
_tmux set-option -g "@claude-signal-running-frames" "A B"
state_sh "$pane_id" --state running
fmt=$(_tmux show-options -wqv -t "$window_id" window-status-format)
case "$fmt" in
  *"#(${TEST_ROOT}/scripts/spinner.sh)"*) ;;
  *) printf '  FAIL [format not wrapped: %q]\n' "$fmt" >&2; _failures=$((_failures + 1)) ;;
esac
assert_eq "running" "$(env_show "TMUX_CLAUDE_SIGNAL_${window_id}_STATE")" "STATE=running"
assert_empty "$(get_style "$window_id")" "running clears bg"

echo "  case: needs-input after running restores format and unsets STATE"
state_sh "$pane_id" --state needs-input
assert_eq "#I:#W" "$(_tmux show-options -wqv -t "$window_id" window-status-format)" "format restored"
assert_env_absent "TMUX_CLAUDE_SIGNAL_${window_id}_STATE" "STATE unset after needs-input"

echo "  case: off after running restores format and unsets STATE"
state_sh "$pane_id" --state running
state_sh "$pane_id" --state off
assert_eq "#I:#W" "$(_tmux show-options -wqv -t "$window_id" window-status-format)" "format restored after off"
assert_env_absent "TMUX_CLAUDE_SIGNAL_${window_id}_STATE" "STATE unset after off"
```

### Step 2.2: test を走らせて FAIL を確認

- [ ] 実行

```bash
bash tests/test-state-transitions.sh
```

期待: FAIL (running case が未実装)

### Step 2.3: state.sh の usage と case 検証に running を追加

- [ ] `scripts/state.sh` の `usage` 関数を編集

```bash
usage() {
  cat <<'EOF' >&2
Usage: state.sh --state <running|needs-input|done|off> [--pane <pane_id>]
EOF
}
```

- [ ] `scripts/state.sh` の case 検証を編集

```bash
case "$state" in
  running|needs-input|done|off) ;;
  *) usage; exit 1 ;;
esac
```

### Step 2.4: state.sh に SCRIPT_DIR と format ラッパー関数を追加

- [ ] `scripts/state.sh` の `clear_style()` の直下に下記を追加

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

wrap_format() {
  local window_id="$1"
  local spinner_cmd="#(${SCRIPT_DIR}/spinner.sh)"
  local fkey="TMUX_CLAUDE_SIGNAL_${window_id}_ORIG_FORMAT"

  save_orig_once "$window_id" "window-status-format" "$fkey"

  local fmt
  fmt=$(tmux show-options -wqv -t "$window_id" window-status-format 2>/dev/null || true)
  if [ -z "$fmt" ]; then
    fmt=$(tmux show-options -gqv window-status-format 2>/dev/null || true)
  fi

  local new_fmt
  if [[ "$fmt" =~ \#I([^#]*)\#W ]]; then
    local sep="${BASH_REMATCH[1]}"
    new_fmt="${fmt//"#I${sep}#W"/"#I${spinner_cmd}#W"}"
  else
    new_fmt="#I ${spinner_cmd} #W"
  fi
  tmux set-window-option -qt "$window_id" window-status-format "$new_fmt"
}

restore_format() {
  local window_id="$1"
  local fkey="TMUX_CLAUDE_SIGNAL_${window_id}_ORIG_FORMAT"
  restore_orig "$window_id" "window-status-format" "$fkey"
}
```

### Step 2.5: case 文を改修して STATE / format / bg の三軸を整合させる

- [ ] `scripts/state.sh` の `window_id=$(tmux display-message ...` の直下に
  `state_key` と `running_frames` を追加

```bash
window_id=$(tmux display-message -p -t "$pane" '#{window_id}')
state_key="TMUX_CLAUDE_SIGNAL_${window_id}_STATE"

running_frames=$(opt_or_default "@claude-signal-running-frames" "")
needs_bg=$(opt_or_default "@claude-signal-needs-input-bg" "yellow")
needs_fg=$(opt_or_default "@claude-signal-needs-input-fg" "black")
done_bg=$(opt_or_default "@claude-signal-done-bg" "red")
done_fg=$(opt_or_default "@claude-signal-done-fg" "black")
```

- [ ] `scripts/state.sh` の case 句を以下に置き換え

```bash
case "$state" in
  running)
    if [ -n "$running_frames" ]; then
      env_set "$state_key" "running"
      clear_style "$window_id"
      wrap_format "$window_id"
    fi
    ;;
  needs-input)
    env_unset "$state_key"
    restore_format "$window_id"
    apply_style "$window_id" "$needs_bg" "$needs_fg"
    ;;
  done)
    env_unset "$state_key"
    restore_format "$window_id"
    apply_style "$window_id" "$done_bg" "$done_fg"
    ;;
  off)
    env_unset "$state_key"
    restore_format "$window_id"
    clear_style "$window_id"
    ;;
esac
```

### Step 2.6: test PASS 確認

- [ ] 実行

```bash
bash tests/test-state-transitions.sh
```

期待: `ok`

- [ ] 全テスト確認

```bash
bash tests/run-all.sh
```

期待: `all tests passed`

### Step 2.7: commit

- [ ] 実行

```bash
git add scripts/state.sh tests/test-state-transitions.sh
git commit -m "feat(state): running case と format wrap を state.sh に追加"
```

## Task 3: format wrap の #I/#W 検出と fallback を別 file で詳細テスト

Files:

- Create: `tests/test-format-wrap.sh`

Interfaces:

- Consumes: Task 2 で実装した state.sh の wrap_format 動作

### Step 3.1: failing test を書く

- [ ] `tests/test-format-wrap.sh` を作成

```bash
#!/usr/bin/env bash
# Verify wrap_format handles common themes and falls back safely.

set -euo pipefail
source "$(dirname "$0")/lib/test-lib.sh"

setup_tmux
trap teardown_tmux EXIT

_tmux new-window -t test
window_id=$(_tmux display-message -p -t test:2 '#{window_id}')
pane_id=$(_tmux display-message -p -t "$window_id" '#{pane_id}')
_tmux select-window -t test:1

_tmux set-option -g "@claude-signal-running-frames" "A B C"

spinner_cmd="#(${TEST_ROOT}/scripts/spinner.sh)"

assert_wrap() {
  local input="$1" expected="$2" label="$3"
  _tmux set-window-option -t "$window_id" window-status-format "$input"
  # ensure we get a fresh ORIG_FORMAT each case
  _tmux set-environment -gu "TMUX_CLAUDE_SIGNAL_${window_id}_ORIG_FORMAT" 2>/dev/null || true
  state_sh "$pane_id" --state running
  assert_eq "$expected" "$(_tmux show-options -wqv -t "$window_id" window-status-format)" "$label"
  state_sh "$pane_id" --state off
}

echo "  case: #I:#W → spinner replaces colon"
assert_wrap "#I:#W" "#I${spinner_cmd}#W" "colon sep"

echo "  case: #I  #W → spinner replaces double space"
assert_wrap "#I  #W" "#I${spinner_cmd}#W" "spaces sep"

echo "  case: #I #W#F → spinner replaces single space, #F stays"
assert_wrap "#I #W#F" "#I${spinner_cmd}#W#F" "space with trailing flag"

echo "  case: no #I/#W → fallback full replace"
assert_wrap "#{window_index}:#{window_name}" "#I ${spinner_cmd} #W" "fallback"

report
```

### Step 3.2: test 実行と PASS 確認

- [ ] 実行

```bash
bash tests/test-format-wrap.sh
```

期待: `ok` (Task 2 で実装済の wrap_format が正しく動作)

### Step 3.3: commit

- [ ] 実行

```bash
git add tests/test-format-wrap.sh
git commit -m "test(format): #I/#W 検出と fallback の詳細テストを追加"
```

## Task 4: focus-ack.sh に STATE=running の skip を追加

Files:

- Modify: `scripts/focus-ack.sh`
- Modify: `tests/test-focus-ack.sh`

Interfaces:

- Consumes: state.sh が立てる `TMUX_CLAUDE_SIGNAL_<window_id>_STATE`
- Produces: focus 時、STATE=running なら ORIG の restore を skip して exit 0

### Step 4.1: failing test を書く

- [ ] `tests/test-focus-ack.sh` の `report` 直前に下記を追加

```bash
echo "  case: focus does not clear running (state persists)"
_tmux set-option -g "@claude-signal-running-frames" "A B"
_tmux set-window-option -t "$window_id" window-status-format "#I:#W"
state_sh "$pane_id" --state running
running_fmt=$(_tmux show-options -wqv -t "$window_id" window-status-format)
_tmux select-window -t "$window_id"
focus_ack_sh "$pane_id" "$window_id"
assert_eq "$running_fmt" "$(_tmux show-options -wqv -t "$window_id" window-status-format)" "running format survives focus"
assert_eq "running" "$(env_show "TMUX_CLAUDE_SIGNAL_${window_id}_STATE")" "STATE survives focus"
```

### Step 4.2: test を走らせて FAIL を確認

- [ ] 実行

```bash
bash tests/test-focus-ack.sh
```

期待: FAIL (現状 focus-ack は STATE 判定を持たず format を unset してしまう)

### Step 4.3: focus-ack.sh に STATE=running の skip 分岐を追加

- [ ] `scripts/focus-ack.sh` の `skey=...` の直前に下記を挿入

```bash
state_key="TMUX_CLAUDE_SIGNAL_${window_id}_STATE"
state=$(env_get "$state_key")
if [ "$state" = "running" ]; then
  exit 0
fi
```

### Step 4.4: test PASS 確認

- [ ] 実行

```bash
bash tests/test-focus-ack.sh
bash tests/run-all.sh
```

期待: 両方 `ok` / `all tests passed`

### Step 4.5: commit

- [ ] 実行

```bash
git add scripts/focus-ack.sh tests/test-focus-ack.sh
git commit -m "feat(focus-ack): STATE=running なら restore を skip する"
```

## Task 5: test-theme-preservation.sh に running 後の theme 復元を追加

Files:

- Modify: `tests/test-theme-preservation.sh`

Interfaces:

- Consumes: Task 2 / Task 4 の動作

### Step 5.1: failing-or-passing test を追加

- [ ] `tests/test-theme-preservation.sh` の `report` 直前に下記を追加

```bash
echo "  case: theme format restored after running → off"
_tmux set-option -g "@claude-signal-running-frames" "A B"
theme_format="#I:#W"
_tmux set-window-option -t "$window_id" window-status-format "$theme_format"
state_sh "$pane_id" --state running
state_sh "$pane_id" --state off
assert_eq "$theme_format" "$(_tmux show-options -wqv -t "$window_id" window-status-format)" "theme format restored"
```

### Step 5.2: test 実行と PASS 確認

- [ ] 実行

```bash
bash tests/test-theme-preservation.sh
bash tests/run-all.sh
```

期待: 両方 OK

### Step 5.3: commit

- [ ] 実行

```bash
git add tests/test-theme-preservation.sh
git commit -m "test(theme): running 後の format 復元を検証"
```

## Task 6: cleanup.sh に @N_STATE と @N_ORIG_FORMAT パターンを追加

Files:

- Modify: `scripts/cleanup.sh`
- Modify: `tests/test-cleanup.sh`

Interfaces:

- Consumes: state.sh / focus-ack.sh が立てる新 env_key
- Produces: 不在 window の `@N_STATE` / `@N_ORIG_FORMAT` を `set-environment -gu` で削除

### Step 6.1: failing test を書く

- [ ] `tests/test-cleanup.sh` の `live_window=...` の直下に下記を追加

```bash
_tmux set-environment -g 'TMUX_CLAUDE_SIGNAL_@999_STATE' running
_tmux set-environment -g 'TMUX_CLAUDE_SIGNAL_@999_ORIG_FORMAT' '#I:#W'
_tmux set-environment -g "TMUX_CLAUDE_SIGNAL_${live_window}_STATE" running
_tmux set-environment -g "TMUX_CLAUDE_SIGNAL_${live_window}_ORIG_FORMAT" '#I:#W'
```

- [ ] 既存 assertion 群の直下 (`assert_eq "bar"... の下) に下記を追加

```bash
assert_env_absent 'TMUX_CLAUDE_SIGNAL_@999_STATE'        "gone window STATE removed"
assert_env_absent 'TMUX_CLAUDE_SIGNAL_@999_ORIG_FORMAT'  "gone window ORIG_FORMAT removed"
assert_eq "running"  "$(env_show "TMUX_CLAUDE_SIGNAL_${live_window}_STATE")"       "live window STATE kept"
assert_eq "#I:#W"    "$(env_show "TMUX_CLAUDE_SIGNAL_${live_window}_ORIG_FORMAT")" "live window ORIG_FORMAT kept"
```

### Step 6.2: test を走らせて FAIL を確認

- [ ] 実行

```bash
bash tests/test-cleanup.sh
```

期待: FAIL (`@999_STATE` / `@999_ORIG_FORMAT` が残る)

### Step 6.3: cleanup.sh のパターンに STATE / ORIG_FORMAT を追加

- [ ] `scripts/cleanup.sh` の case 句を編集

```bash
case "$key" in
  TMUX_CLAUDE_SIGNAL_DIR)
    ;;
  TMUX_CLAUDE_SIGNAL_%*)
    tmux set-environment -gu "$key" 2>/dev/null || true
    ;;
  TMUX_CLAUDE_SIGNAL_@[0-9]*_ORIG_STYLE|TMUX_CLAUDE_SIGNAL_@[0-9]*_ORIG_CURRENT|TMUX_CLAUDE_SIGNAL_@[0-9]*_ORIG_FORMAT|TMUX_CLAUDE_SIGNAL_@[0-9]*_STATE)
    wid=$(printf '%s' "$key" | sed -E 's/^TMUX_CLAUDE_SIGNAL_(@[0-9]+)_.*/\1/')
    [ -z "$wid" ] && continue
    if ! printf '%s\n' "$existing" | grep -qx "$wid"; then
      tmux set-environment -gu "$key" 2>/dev/null || true
    fi
    ;;
  *)
    ;;
esac
```

### Step 6.4: test PASS 確認

- [ ] 実行

```bash
bash tests/test-cleanup.sh
bash tests/run-all.sh
```

期待: 両方 OK

### Step 6.5: commit

- [ ] 実行

```bash
git add scripts/cleanup.sh tests/test-cleanup.sh
git commit -m "feat(cleanup): @N_STATE と @N_ORIG_FORMAT を掃除対象に追加"
```

## Task 7: hooks/claude-hooks.json の PreToolUse を running に変更

Files:

- Modify: `hooks/claude-hooks.json`

Interfaces:

- Consumes: state.sh の running case
- Produces: Claude Code の PreToolUse hook で `state.sh --state running` が発火

### Step 7.1: hooks/claude-hooks.json を編集

- [ ] PreToolUse の command を編集

```json
"PreToolUse": [
  {
    "matcher": "",
    "hooks": [
      {
        "type": "command",
        "command": "\"${TMUX_CLAUDE_SIGNAL_DIR:-$HOME/.tmux/plugins/tmux-claude-signal}\"/scripts/state.sh --state running"
      }
    ]
  }
],
```

UserPromptSubmit / PermissionRequest / Stop の各 hook は変更しない。

### Step 7.2: 全テスト確認

- [ ] 実行

```bash
bash tests/run-all.sh
```

期待: `all tests passed`

### Step 7.3: commit

- [ ] 実行

```bash
git add hooks/claude-hooks.json
git commit -m "feat(hooks): PreToolUse で running を発火"
```

## Task 8: README.md と CLAUDE.md を更新

Files:

- Modify: `README.md`
- Modify: `CLAUDE.md`

### Step 8.1: README.md に running 行と設定例を追加

- [ ] `README.md` の状態表に running 行を追加 (needs-input 行の上に挿入)

```markdown
| state       | Claude Code hook  | default visual | cleared by          |
| ----------- | ----------------- | -------------- | ------------------- |
| running     | PreToolUse        | スピナー (opt-in) | 次の状態          |
| needs-input | PermissionRequest | 💛 yellow      | focus or next state |
| done        | Stop              | ❤️ red         | focus or next state |
```

- [ ] 設定例セクションに下記を追加

```tmux
set -g @claude-signal-running-frames "⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏"
```

frames は空白区切りで設定する。
未設定なら running hook が来ても何も表示されない (opt-in)。
spinner は `#I` と `#W` の間に注入され、focus しても消えない。

### Step 8.2: CLAUDE.md の Glossaries と Constraints を更新

- [ ] `CLAUDE.md` の Glossaries に running 行を追加 (needs-input の上)

```markdown
- running: Claude Code が tool を実行中 (PreToolUse 発火後)。
  `@claude-signal-running-frames` 設定時のみスピナーを表示。focus 永続。
```

- [ ] Constraints セクションの末尾に下記を追加

```markdown
- running は format 軸 (window-status-format) で表現し bg は触らない。
  needs-input/done との完全排他、focus 永続を維持する。
- spinner.sh は tmux `#()` から 1 秒粒度で呼ばれる stateless スクリプト。
  frames は `@claude-signal-running-frames` にスペース区切りで設定する。
```

### Step 8.3: 全テスト最終確認

- [ ] 実行

```bash
bash tests/run-all.sh
```

期待: `all tests passed`

### Step 8.4: commit

- [ ] 実行

```bash
git add README.md CLAUDE.md
git commit -m "docs(running): README と CLAUDE.md に running 仕様を反映"
```

## 完了基準

- [ ] `bash tests/run-all.sh` が全 pass
- [ ] 既存テスト (state-transitions / focus-ack / theme-preservation / cleanup) が
  running 経路を含めて pass
- [ ] 新規テスト (running-spinner / format-wrap) が pass
- [ ] git log に Task 1〜8 の commit が並ぶ
- [ ] 確定判断 (running の表現方式 = spinner、opt-in 方針) を
  `docs/DECISIONS.md` に 1 行で上げる

## Prototype validation (実装後)

ghostty + tmux + Claude Code 実機で以下の frames を切り替え見栄えを確認:

- `⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏` (周期 10 秒、ほぼ静止)
- `⠋ ⠙ ⠹ ⠸` (周期 4 秒)
- `✶ ✱ ✣ ✳` (周期 4 秒、Claude 風)
- `● ○` (周期 2 秒、明滅)

選定後、README 推奨例として 1 種に絞り別 commit で更新する。
