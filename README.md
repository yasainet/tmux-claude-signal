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

| state | Claude Code hook | visual |
|---|---|---|
| running | UserPromptSubmit | clear |
| needs-input | PermissionRequest | yellow window-status |
| done | Stop | red window-status (clears on focus) |

Override colors with these options.

```tmux
set -g @claude-signal-needs-input-bg 'yellow'
set -g @claude-signal-needs-input-fg 'black'
set -g @claude-signal-done-bg 'red'
set -g @claude-signal-done-fg 'black'
```
