# running 状態をスピナー TUI component で表現する

## 背景

needs-input / done の 2 状態に加え actively running な pane を可視化したい。

過去にも opt-in の running 色を導入したが (commit 3c9a6fe)、focus 永続な
背景色がノイズと判断され削除された (commit 2722863)。
真因は「focus 永続自体」ではなく「actively running の bg 表示が
attention 信号としての value を持たなかった」ことにある。

今回は背景色ではなく、Claude Code TUI でよく使われるスピナーを
window-status タブの `#I` と `#W` の間に注入することで running を表現する。

## ゴール

actively running な pane を window-status 上のスピナーで可視化する。
needs-input / done との完全排他遷移を維持する。
focus 永続 (focus してもスピナーは消えない) を実現する。
opt-in (`@claude-signal-running-frames` 未設定でゼロ影響) で導入する。

## 非ゴール

100ms 級の滑らかなアニメーションは tmux native では実現不能なため非対応。
1 秒粒度 (status-interval 最小値) の動きで妥協する。
外部 daemon プロセスによる高頻度更新は YAGNI とする。

bg と spinner の同時表示は非対応とする (完全排他)。

複数 pane が同じ window 内で別々の Claude セッションを動かすケースは
現状 plugin と同じく非対応 (1 window 1 pane 前提)。

## 設計

### アーキテクチャ

state を 2 つの軸に分離する。

- `window-status-style` (bg/fg): needs-input / done のみ上書き
- `window-status-format`: running のみ上書き (spinner 注入)

両方とも `__ORIG_*__` env_key を介した save_orig_once / restore で
テーマ値を保護する。

window_id ベースの `STATE` env_key を追加し focus-ack の skip 判定に使う。
spinner の有効/無効は format wrap が当たっているかどうかで決まるため
spinner.sh 側に STATE 判定は不要となる。

### コンポーネント

scripts/ の変更内容:

- `state.sh` 既存 + running case + format wrap 関数を inline
- `spinner.sh` 新規。`#()` から呼ばれ 1 文字を返す
- `focus-ack.sh` STATE=running なら exit の 1 分岐を追加
- `cleanup.sh` `@N_STATE` と `@N_ORIG_FORMAT` パターンを追加

hooks/ の変更内容:

- `claude-hooks.json` PreToolUse の off を running に変更

format wrap は state.sh 内のローカル関数として inline する。
ファイル数増加を最小化し既存 plugin の構成スタイルに揃える。

### 遷移マトリクス

各 state の動作を 4 項目で記述する。

running:

- STATE: set "running"
- bg: restore (テーマに戻す)
- format: wrap (ORIG save → spinner 注入)

needs-input:

- STATE: unset
- bg: apply yellow
- format: restore (ORIG_FORMAT)

done:

- STATE: unset
- bg: apply red
- format: restore (ORIG_FORMAT)

off:

- STATE: unset
- bg: restore
- format: restore

### opt-in API

`@claude-signal-running-frames` をスペース区切りで設定する。
未設定なら running hook が来ても spinner は表示されず no-op となる。

```tmux
set -g @claude-signal-running-frames "⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏"
```

frames セットは設定有無を兼ねるため、専用 toggle option は持たない。

### format wrap ロジック

擬似コード:

```bash
fmt=$(show-options window-status-format)
save_orig_once "$window_id" window-status-format "$fmt_orig_key"

if [[ "$fmt" =~ \#I([^#]*)\#W ]]; then
  sep="${BASH_REMATCH[1]}"
  new_fmt="${fmt/#I${sep}#W/#I#(${SCRIPT_DIR}/spinner.sh)#W}"
else
  new_fmt="#I #(${SCRIPT_DIR}/spinner.sh) #W"   # fallback
fi
set-window-option window-status-format "$new_fmt"
```

`[^#]*` で `#I` と `#W` の間に他の format directive がない
シンプルなセパレータのみを対象とする。
検出失敗時は format 全置換 fallback で graceful に逃げる。

### spinner.sh の実装

```bash
#!/usr/bin/env bash
frames=$(tmux show-option -gqv "@claude-signal-running-frames" 2>/dev/null || true)
[ -z "$frames" ] && exit 0
IFS=' ' read -ra arr <<< "$frames"
i=$(( $(date +%s) % ${#arr[@]} ))
printf ' %s ' "${arr[$i]}"
```

frames をスペース区切りで設定し UTF-8 切り出しの locale 依存を回避する。
全 window で同じフレーム (時刻ベースのグローバル位相) とし
fork ごとに stateless で動く。

### data flow

```
plugin source ─► cleanup.sh が不在 window の env を掃除
UserPromptSubmit ─► state.sh --state off
                  ─► STATE unset, bg restore, format restore
PreToolUse ─► state.sh --state running
            ─► ORIG_FORMAT save, format wrap, STATE=running
                  │
                  ▼ tmux が 1 秒ごとに評価
               spinner.sh ─► frame index = epoch_sec % len(frames)
PermissionRequest ─► state.sh --state needs-input
                  ─► STATE unset, format restore, bg=yellow apply
Stop ─► state.sh --state done
     ─► STATE unset, format restore, bg=red apply
focus (3 hooks) ─► focus-ack.sh
                ─► STATE=running なら exit、それ以外 restore
```

### エラーハンドリング

tmux 不在: scripts が早期 exit 0。spinner.sh も同パターンで揃える。

frames 未設定: running hook 来ても no-op。opt-in の自然な動作。

`#I`/`#W` 検出失敗: fallback 全置換に逃がす。
テーマ独自要素は running 中のみ失われる。

spinner.sh の出力空: spinner 欄が一瞬空になる。
次の評価で復帰し致命的でない。

ORIG_FORMAT 消失: spinner が永続表示で残る恐れがある。
cleanup.sh が掃除し、手動 off で復帰可能。

並列 PreToolUse: 同じ format を多重 set。
実機 20 並列で race が起きないことを検証済み。

### TOCTOU の扱い

save_orig_once は env_key 既存ならスキップする冪等チェックがある。
通常は race にならない。
実機 20 並列検証で ORIG が wrap 済 format に汚染される事象は再現しなかった。

初期実装は冪等性のみに依存する。
運用で問題が出たら自己検出マーカ (format コメントへの sentinel 埋め込み)
を追加する方針とする。

## テスト

### Integration (detached tmux server)

tests/ の変更内容:

- 既存 `test-state-transitions.sh` running 経路を追加
- 既存 `test-theme-preservation.sh` running 後の theme 復元を追加
- 既存 `test-focus-ack.sh` STATE=running 時の skip を追加
- 既存 `test-cleanup.sh` `@N_STATE` / `@N_ORIG_FORMAT` 掃除を追加
- 新規 `test-running-spinner.sh` spinner 出力、frames 設定有無、index 計算
- 新規 `test-format-wrap.sh` `#I`/`#W` 検出と fallback

### Manual / Prototype validation

frames セットと 1 秒粒度の体感は実装後に実機で確認する。
実機環境は ghostty + tmux + Claude Code on tmux で確定している。

候補 frames を切り替えて見栄えを比較する。
README 推奨例として 1 種に絞り込む。

候補 frames 一覧:

- `⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏` 周期 10 秒、動きはほぼ静止
- `⠋ ⠙ ⠹ ⠸` 周期 4 秒、動きは普通
- `✶ ✱ ✣ ✳` 周期 4 秒、Claude 風
- `● ○` 周期 2 秒、明滅

設定 option としては自由カスタマイズ可能なまま残す。

## 確定判断

本 spec で確定した判断のうち scaffold を超えて参照され続けるものは
`docs/DECISIONS.md` に 1 行で上げる。
具体的には running の表現方式 (spinner) と opt-in 方針の 2 点を上げる。
