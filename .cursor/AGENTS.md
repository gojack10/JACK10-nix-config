# Project Context

## IMPORTANT: CLAUDE.md / AGENTS.md Parity

**CLAUDE.md and AGENTS.md must remain identical at all times.** After any changes to either file, sync with:

```bash
cp CLAUDE.md AGENTS.md && cp CLAUDE.md .cursor/AGENTS.md
```

## Sudo Command Constraints

When running sudo commands:

1. **No chaining** - Cannot use `&&` or `;` with sudo
2. **No piping** - Cannot pipe to/from sudo commands
3. **No direct writes** - Cannot write files directly with sudo

**Workaround for writing files as root:**
```bash
# First write to /tmp/
echo "content" > /tmp/myfile
# Then move with sudo
sudo cp /tmp/myfile /etc/destination
```

## Git Commit Workflow

For commits, follow `/Users/jack/.pi/agent/skills/git-commit/SKILL.md`. It is authoritative for commit format, branch naming, staging, and push behavior.

Do not add `Co-Authored-By` trailers.
