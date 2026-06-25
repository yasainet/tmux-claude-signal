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
| running     | PreToolUse        | スピナー (opt-in) | 次の状態          |
| needs-input | PermissionRequest | 💛 yellow      | focus or next state |
| done        | Stop              | ❤️ red         | focus or next state |

### Sample

![window-status example](docs/images/window-status.png)

Attention signals clear as soon as you focus the window.
Resuming work (UserPromptSubmit / PreToolUse) also clears any stale signal.

Override colors with these options.

```tmux
set -g @claude-signal-needs-input-bg 'yellow'
set -g @claude-signal-needs-input-fg 'black'
set -g @claude-signal-done-bg 'red'
set -g @claude-signal-done-fg 'black'
```

Optionally add a spinner to show while Claude Code is executing tools.

```tmux
set -g @claude-signal-running-frames "⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏"
```

frames は空白区切りで設定する。
未設定なら running hook が来ても何も表示されない (opt-in)。
spinner は `#I` と `#W` の間に注入され focus しても消えない。

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
