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
sudo mv /tmp/myfile /etc/destination
```

## Git Commit Conventions

Use Conventional Commits format. Max 100 char title.

### Commit Types

| Type | Description |
|------|-------------|
| `feat` | New feature for the user |
| `fix` | Bug fix for the user |
| `docs` | Documentation changes |
| `style` | Formatting, no code change |
| `refactor` | Refactoring, no behavior change |
| `test` | Adding/refactoring tests |
| `chore` | Build tasks, no code change |
| `perf` | Performance improvements |
| `build` | Build system or dependencies |
| `ci` | CI config changes |
| `revert` | Reverts a previous commit |

### Scope

One token, kebab-case. Use domain/subsystem over file paths. Omit if cross-cutting.

Common scopes: `auth`, `api`, `db`, `ui`, `tree`, `llm`, `chat`, `context`, `parser`

### Format

```
type(scope): imperative description

CHANGES:

- Bullet describing change (7-10 words each)
- Another change
```

### Branch Naming

```
<type>[optional-scope]/<ticket>-<short-slug>
```

Examples:
- `feat/auth/123-add-login-form`
- `fix/parser-handle-nested-blocks`
- `refactor/llm-split-prompt-sections`

### Large Diffs

Segment into logical commits. Output with:

```bash
git add <files>
```

```
type(scope): description

CHANGES:

- Change 1
- Change 2
```
