#!/bin/sh
# Claude Code PreToolUse hook (matcher Bash) of the Diakrin plugin. It reads the tool call on stdin and lets Diakrin's local engine
# answer "allow" only for the engine's own commands (pull, dev, check, save, with a strict grammar). For any other command it prints
# nothing, so Claude Code asks the person as usual; it never answers "deny". Without the engine installed it prints nothing.
# It lives in a script because Anthropic's plugin directory accepts no variable but ${CLAUDE_PLUGIN_ROOT} in a hook command.
engine="$HOME/.diakrin/bin/diakrin"
if [ -x "$engine" ]; then
  "$engine" hook approve --host claude-code || true
fi
exit 0
