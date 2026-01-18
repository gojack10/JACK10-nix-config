# Claude Code Project Config

## Sudo
Always use `sudo -A` for all sudo commands. This triggers the wofi askpass helper for GUI password prompts.

**Limitations:**
- Cannot chain multiple `sudo -A` commands (e.g., `sudo -A cmd1 && sudo -A cmd2`) - run them as separate Bash tool calls
- Heredocs/EOF don't work with `sudo -A tee` - write to `/tmp/` first, then `sudo -A cp` to destination
- **No piping or redirection at all** - the askpass prompt won't appear if stdout/stderr is redirected or piped. This includes:
  - `sudo -A cmd | something` - fails
  - `sudo -A cmd 2>/dev/null` - fails
  - `sudo -A cmd || echo "fallback"` - fails
  - Always run `sudo -A` commands completely bare with no shell operators
