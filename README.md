# enever

Protect your secrets from AI coding assistants.

AI tools like Claude Code, Cursor, and Copilot automatically read your `.env` files, exposing API keys and passwords to their context. **enever** forces AI to use masked values instead.

```bash
npm install -g enever
```

## How It Works

```bash
enever read
# DATABASE_URL:
#   .env:            ****host/dev
#   .env.production: ****host/prod
# API_KEY:
#   .env:            ****t123
#   .env.production: ****t456
```

All values are masked by default. AI sees `****t123`, not your actual secrets.

## Commands

| Command | Description |
|---------|-------------|
| `enever read` | Read all variables (masked) |
| `enever read KEY` | Read specific variable |
| `enever read ./path` | Read from another directory |
| `enever write KEY=value` | Write to .env.local |
| `enever write --file .env.prod KEY=val` | Write to specific file |
| `enever delete KEY` | Delete from .env.local |
| `enever diff .env .env.prod` | Compare two files |
| `enever list` | List keys only (no values) |
| `enever read -u KEY` | Unmask a specific key |
| `enever read --json` | JSON output |

## Setup for AI Protection

### 1. Agent Skill

Create `.skills/env-management/SKILL.md`:

```yaml
---
name: env-management
description: |
  Safely access environment variables. Use when checking env vars,
  API keys, database URLs, or any .env file contents.
  ALWAYS use enever CLI instead of reading .env files directly.
allowed-tools: Bash(enever:*)
---

# Environment Variable Management

Use `enever` for all .env operations. Values are masked by default.

## Commands

- `enever list` - List all keys (no values)
- `enever read` - Read all variables (masked)
- `enever read KEY` - Read specific variable
- `enever write KEY=value` - Write to .env.local
- `enever delete KEY` - Delete from .env.local

## Rules

1. NEVER read .env files directly
2. NEVER use cat/grep/head on .env files
3. ALWAYS use enever commands
```

### 2. AGENTS.md

Create `AGENTS.md` in project root:

```markdown
# AI Agent Guidelines

## Environment Variables

Use `enever` for all .env operations. Do not read .env files directly.

- `enever list` - see available keys
- `enever read` - see masked values
- `enever write KEY=value` - modify .env.local
```

### 3. Block Direct Access (Claude Code)

Create `.claude/settings.json`:

```json
{
  "permissions": {
    "deny": [
      "Read(.env)", "Read(.env.*)", "Read(**/.env)", "Read(**/.env.*)",
      "Bash(cat:*.env*)", "Bash(grep:*.env*)"
    ],
    "allow": ["Bash(enever:*)"]
  }
}
```

## Why This Works

- **[Agent Skills](https://agentskills.io)** - Open standard supported by Claude, Cursor, Copilot, Codex, and 25+ AI tools
- **AGENTS.md** - Universal instructions read by all major AI assistants
- **Permission blocks** - Hard blocks prevent direct .env access

## Installation

```bash
# npm
npm install -g enever

# or use directly
npx enever read
```

Pre-built binaries available on [GitHub Releases](https://github.com/itaylisaey/enever/releases).

## License

MIT
