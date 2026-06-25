# tmux-claude-signal

Window-status color signal for Claude Code panes inside the current tmux session.

## Setup

Install via TPM by adding the line below to `~/.tmux.conf` and pressing `prefix + I`.

```tmux
set -g @plugin 'yasainet/tmux-claude-signal'
```

Then merge `hooks/claude-hooks.json` into `~/.claude/settings.json` so Claude Code reports state transitions.

Sourcing the plugin auto-cleans env from past schemas and missing windows.

## Usage

Each Claude Code pane reports state via window-status.

| state       | Claude Code hook  | default visual | cleared by |
| ----------- | ----------------- | -------------- | ---------- |
| needs-input | PermissionRequest | 💛 yellow      | focus or next state |
| done        | Stop              | ❤️ red         | focus or next state |

### Sample

![window-status example](docs/images/window-status.png)

Color persists until the window gains focus, acting as an unread mark.
Resuming work (UserPromptSubmit / PreToolUse) also clears stale signals.

### Cross-session indicator

`scripts/cross-session.sh '#{client_session}'` emits a tmux format chip
that reflects whether any other session has a non-idle window.
Embed it in your theme's `status-right` wherever you want the chip:

```tmux
set -g status-right "#(#{TMUX_CLAUDE_SIGNAL_DIR}/scripts/cross-session.sh '#{client_session}')..."
```

The chip is always rendered; only its color changes.

- idle (no other session non-idle): muted blue background
- active (any other session non-idle): green background

Kind (needs-input vs done) is not distinguished.
The chip signals only that something elsewhere needs attention.

Override colors with these options.

```tmux
set -g @claude-signal-needs-input-bg 'yellow'
set -g @claude-signal-needs-input-fg 'black'
set -g @claude-signal-done-bg 'red'
set -g @claude-signal-done-fg 'black'
```

### Debug log

Enable opt-in logging to trace behavior.

```tmux
set -g @claude-signal-debug 1
```

The default output path is `/tmp/claude-signal.log`.
Set `TMUX_CLAUDE_SIGNAL_LOG` in the tmux env to use a different path.

```sh
tmux set-environment -g TMUX_CLAUDE_SIGNAL_LOG "$HOME/.cache/claude-signal.log"
```

Entry points of `state.sh` and `focus-ack.sh`, plus APPLY / CLEAR decisions are logged.
Nothing is written when the option is unset (the default).
