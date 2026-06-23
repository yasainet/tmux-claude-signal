# tmux-claude-signal

Window-status color signal for Claude Code panes inside the current tmux session.

## Setup

Install via TPM by adding the line below to `~/.tmux.conf` and pressing `prefix + I`.

```tmux
set -g @plugin 'yasainet/tmux-claude-signal'
```

Then merge `hooks/claude-hooks.json` into `~/.claude/settings.json` so Claude Code reports state transitions.

## Usage

Each Claude Code pane reports one of three states.

| state | Claude Code hook | default visual | cleared by |
|---|---|---|---|
| running | UserPromptSubmit | clear (opt-in color) | next state |
| needs-input | PermissionRequest | yellow | focus or next state |
| done | Stop | red | focus or next state |

Override colors with these options.

```tmux
set -g @claude-signal-running-bg 'green'
set -g @claude-signal-running-fg 'black'
set -g @claude-signal-needs-input-bg 'yellow'
set -g @claude-signal-needs-input-fg 'black'
set -g @claude-signal-done-bg 'red'
set -g @claude-signal-done-fg 'black'
```

The running color is opt-in (no color by default).
Set both bg and fg to enable it.
The configured running color persists across window focus.
