# Claude Code Project Config

## Sudo
Always use `sudo -A` for all sudo commands. This triggers the wofi askpass helper for GUI password prompts.

**Limitations:**
- Cannot chain multiple `sudo -A` commands (e.g., `sudo -A cmd1 && sudo -A cmd2`) - run them as separate Bash tool calls
- Heredocs/EOF don't work with `sudo -A tee` - write to `/tmp/` first, then `sudo -A cp` to destination
- Piping to `sudo -A tee` also fails silently
