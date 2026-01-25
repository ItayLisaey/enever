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
| `enever read -u KEY` | Unmask a specific key |
| `enever read --json` | JSON output |
| `enever write KEY=value` | Write to .env.local |
| `enever write -f .env.prod KEY=val` | Write to specific file |
| `enever write --force KEY=val` | Overwrite existing keys |
| `enever delete KEY` | Delete from .env.local |
| `enever delete -f .env.prod KEY` | Delete from specific file |
| `enever diff .env .env.prod` | Compare two files |
| `enever list` | List keys only (no values) |

### Options

| Flag | Description |
|------|-------------|
| `-u, --unmask <key>` | Show raw value of a key |
| `-f, --file <path>` | Target file for write/delete (default: .env.local) |
| `--force` | Overwrite existing keys (write command) |
| `--json` | Output in JSON format |
| `-q, --quiet` | Suppress non-essential output |
| `-h, --help` | Show help |
| `-v, --version` | Show version |

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Key not found |
| 3 | Key exists (write without --force) |

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
- `enever read -u KEY` - Read unmasked value
- `enever read ./path` - Read from another directory
- `enever write KEY=value` - Write to .env.local
- `enever write -f FILE KEY=value` - Write to specific file
- `enever write --force KEY=value` - Overwrite existing keys
- `enever delete KEY` - Delete from .env.local
- `enever delete -f FILE KEY` - Delete from specific file
- `enever diff .env .env.prod` - Compare two files

## Options

- `-u, --unmask KEY` - Show raw value
- `-f, --file PATH` - Target file for write/delete
- `--force` - Overwrite existing keys
- `--json` - JSON output
- `-q, --quiet` - Suppress output

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

Use `enever` CLI for all .env operations. Do not read .env files directly.

### Commands

- `enever list` - see available keys
- `enever read` - see masked values
- `enever read KEY` - read specific key
- `enever write KEY=value` - write to .env.local
- `enever write -f .env.prod KEY=value` - write to specific file
- `enever delete KEY` - delete from .env.local
- `enever diff .env .env.prod` - compare files

### Rules

1. NEVER read .env files directly with cat/grep/head
2. ALWAYS use enever commands for env operations
3. Values are masked by default for security
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
