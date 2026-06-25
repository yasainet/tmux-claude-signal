# tmux-claude-signal

Window-status color signal for Claude Code panes inside the current tmux session.

## Setup

Install via TPM by adding the line below to `~/.tmux.conf` and pressing `prefix + I`.

```tmux
set -g @plugin 'yasainet/tmux-claude-signal'
```

Then merge `hooks/claude-hooks.json` into `~/.claude/settings.json` so Claude Code reports state transitions.

Plugin source 時に過去スキーマと不在 window 由来の env を自動掃除します。

## Usage

Each Claude Code pane reports state via window-status.

| state       | Claude Code hook  | default visual | cleared by          |
| ----------- | ----------------- | -------------- | ------------------- |
| running     | PreToolUse        | 💚 green       | 次の状態            |
| needs-input | PermissionRequest | 💛 yellow      | focus or next state |
| done        | Stop              | ❤️ red         | focus or next state |

### Sample

![window-status example](docs/images/window-status.png)

needs-input / done は focus でクリアされる。
running は focus しても色が残り、次の状態に遷移するまで保持される。
Resuming work (UserPromptSubmit / PreToolUse) も stale signal をクリアする。

Override colors with these options.

```tmux
set -g @claude-signal-running-bg '#9ece6a'
set -g @claude-signal-running-fg '#15161e'
set -g @claude-signal-needs-input-bg 'yellow'
set -g @claude-signal-needs-input-fg 'black'
set -g @claude-signal-done-bg 'red'
set -g @claude-signal-done-fg 'black'
```

### Debug log

挙動を追跡したい場合は opt-in でログを記録できる。

```tmux
set -g @claude-signal-debug 1
```

デフォルトの出力先は `/tmp/claude-signal.log`。
別パスにしたい場合は `TMUX_CLAUDE_SIGNAL_LOG` を tmux env に設定する。

```sh
tmux set-environment -g TMUX_CLAUDE_SIGNAL_LOG "$HOME/.cache/claude-signal.log"
```

`state.sh` と `focus-ack.sh` の入口、APPLY / CLEAR / RESTORE / ACTIVE 判定が記録される。
未設定 (デフォルト) なら一切書き込まない。
