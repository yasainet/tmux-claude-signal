# Debug logger. No-op unless @claude-signal-debug = 1.
# Source this file; do not execute directly.

sig_log_enabled() {
  command -v tmux >/dev/null 2>&1 || return 1
  local v
  v=$(tmux show-option -gqv "@claude-signal-debug" 2>/dev/null || true)
  case "$v" in 1|on|true) return 0 ;; *) return 1 ;; esac
}

sig_log() {
  sig_log_enabled || return 0
  local path="${TMUX_CLAUDE_SIGNAL_LOG:-/tmp/claude-signal.log}"
  printf '%s pid=%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$$" "$*" >> "$path" 2>/dev/null || true
}
