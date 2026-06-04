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
| `enever copy <src> <dst> [KEY...]` | Copy env vars between files (values never printed) |
| `enever exec -- <cmd>` | Run a command with real env vars injected (never printed) |
| `enever schema` | Machine-readable CLI schema (JSON, for agents) |

### Options

| Flag | Description |
|------|-------------|
| `-u, --unmask <key>` | Show raw value of a key |
| `-f, --file <path>` | Target file for write/delete (default: .env.local) |
| `--force`, `-y, --yes` | Overwrite existing keys (write command) |
| `-n, --dry-run` | Preview write/delete without modifying files |
| `--json` | Output in JSON format (structured errors on stderr) |
| `--no-color` | Disable color (no-op; enever never emits color) |
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
| 64 | Usage error (invalid arguments) |

## For AI Agents

`enever` is built to be driven by agents and scripts. Every command is
pipeable and supports machine-readable output.

**Self-discovery.** Run `enever schema` for a stable JSON description of every
command, flag, and exit code — an agent can learn the whole surface in one call:

```bash
enever schema | jq '.commands[].name'
```

**Structured output.** Pass `--json` to any command for a documented shape:

```bash
enever list --json            # {"keys":["API_KEY","DATABASE_URL"]}
enever read --json            # {"API_KEY":[{"file":".env","value":"****t123"}]}
enever diff .env .env.prod --json
#   {"diff":[{"key":"A","status":"removed"},{"key":"B","status":"changed"}]}
enever write FOO=bar --json   # {"written":[{"key":"FOO"}],"file":".env.local","dry_run":false}
enever delete FOO --json      # {"deleted":["FOO"],"not_found":[],"file":".env.local","dry_run":false}
```

**Structured errors.** In `--json` mode, errors go to **stderr** as a stable
envelope so stdout stays clean and parseable:

```bash
enever read MISSING --json    # stderr: {"error":{"code":"KEY_NOT_FOUND","message":"...","hint":"..."}}
```

**Safe by default.** Values are masked unless you pass `-u/--unmask`. Use
`-n/--dry-run` to preview `write`/`delete` without touching files, and
`--force`/`-y` to opt into overwriting existing keys non-interactively.

**Run commands without exposing secrets.** `enever exec` loads the real
(unmasked) values, injects them into a child process's environment, and runs
it — the secrets reach the program but are never printed to the terminal or an
agent's context:

```bash
enever exec -- npm run dev          # child gets real env; nothing is printed
enever exec -f .env.prod -- node app.js
```

The child's stdout/stderr pass straight through and its exit code is
propagated (`127` if the command isn't found, `126` if not executable). When
multiple files define a key, the most specific wins
(`.env` < `.env.<mode>` < `.env.local` < `.env.<mode>.local`).

**Copy secrets between files.** `enever copy` reads the real values from a
source (a file or a directory of `.env*` files) and writes them into a
destination `.env` file. The values are copied but never printed:

```bash
enever copy . .env.staging            # copy every key into .env.staging
enever copy ./other-svc .env API_KEY  # copy one key from another project
enever copy . .env.prod --force       # overwrite keys that already exist
```

Existing destination keys are preserved unless `--force`; `--json` reports
`copied`, `skipped`, and `not_found`. Use `-n/--dry-run` to preview.

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

## Discovering the interface

Run `enever schema` for a machine-readable JSON description of every command,
flag, and exit code. Add `--json` to any command for structured output.

## Commands

- `enever schema` - JSON description of the whole CLI (run this first)
- `enever list` - List all keys (no values)
- `enever read` - Read all variables (masked)
- `enever read KEY` - Read specific variable
- `enever read -u KEY` - Read unmasked value
- `enever read ./path` - Read from another directory
- `enever write KEY=value` - Write to .env.local
- `enever write -f FILE KEY=value` - Write to specific file
- `enever write --force KEY=value` - Overwrite existing keys
- `enever write -n KEY=value` - Dry-run (preview, no write)
- `enever delete KEY` - Delete from .env.local
- `enever delete -f FILE KEY` - Delete from specific file
- `enever diff .env .env.prod` - Compare two files
- `enever copy SRC DST [KEY...]` - Copy env vars from SRC into DST (values never printed)
- `enever exec -- CMD ARGS` - Run CMD with real env vars injected (values never printed)

## Options

- `-u, --unmask KEY` - Show raw value
- `-f, --file PATH` - Target file for write/delete
- `--force`, `-y` - Overwrite existing keys
- `-n, --dry-run` - Preview write/delete without writing
- `--json` - JSON output (structured errors on stderr)
- `-q, --quiet` - Suppress output

## Rules

1. NEVER read .env files directly
2. NEVER use cat/grep/head on .env files
3. ALWAYS use enever commands
4. Use `--json` for parseable output and check exit codes (0 ok, 2 not-found, 3 exists, 64 usage)
```

### 2. AGENTS.md

Create `AGENTS.md` in project root:

```markdown
# AI Agent Guidelines

## Environment Variables

Use `enever` CLI for all .env operations. Do not read .env files directly.

### Commands

- `enever schema` - machine-readable JSON of all commands/flags/exit codes
- `enever list` - see available keys
- `enever read` - see masked values
- `enever read KEY` - read specific key
- `enever write KEY=value` - write to .env.local
- `enever write -f .env.prod KEY=value` - write to specific file
- `enever delete KEY` - delete from .env.local
- `enever diff .env .env.prod` - compare files

Add `--json` to any command for structured output; errors are emitted to
stderr as `{"error":{"code","message","hint"}}`.

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
