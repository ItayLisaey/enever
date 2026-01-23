# enever

Secure environment variable management for your projects.

**enever** masks sensitive values by default, reads all `.env.*` files simultaneously, and provides audit logging for compliance.

## Features

- **Security-first**: All values masked by default, explicit unmasking required
- **Multi-file view**: See values from all `.env.*` files at once
- **Zero dependencies**: Single static binary, works everywhere

## Installation

### Pre-built binaries

Download from [GitHub Releases](https://github.com/itaylisaey/enever/releases):

```bash
# macOS (Apple Silicon)
curl -L https://github.com/itaylisaey/enever/releases/latest/download/enever-darwin-aarch64.tar.gz | tar xz
sudo mv enever /usr/local/bin/

# macOS (Intel)
curl -L https://github.com/itaylisaey/enever/releases/latest/download/enever-darwin-x86_64.tar.gz | tar xz
sudo mv enever /usr/local/bin/

# Linux (x64)
curl -L https://github.com/itaylisaey/enever/releases/latest/download/enever-linux-x86_64.tar.gz | tar xz
sudo mv enever /usr/local/bin/

# Linux (arm64)
curl -L https://github.com/itaylisaey/enever/releases/latest/download/enever-linux-aarch64.tar.gz | tar xz
sudo mv enever /usr/local/bin/
```

### Build from source

Requires [Zig](https://ziglang.org/) 0.15.0+:

```bash
git clone https://github.com/itaylisaey/enever.git
cd enever
zig build -Doptimize=ReleaseSafe
./zig-out/bin/enever --version
```

## Quick Start

```bash
# Create some .env files
echo "DATABASE_URL=postgres://localhost/dev" > .env
echo "API_KEY=sk_dev_secret123" >> .env

echo "DATABASE_URL=postgres://prod-server/app" > .env.production
echo "API_KEY=sk_prod_secret456" >> .env.production

# View all variables (shows values from each file)
enever get
# DATABASE_URL:
#   .env:            ****ost/dev
#   .env.production: ****ver/app
# API_KEY:
#   .env:            ****t123
#   .env.production: ****t456

# Get a specific key
enever get API_KEY
# .env:            ****t123
# .env.production: ****t456

# Unmask a specific key
enever get -u API_KEY
# .env:            sk_dev_secret123
# .env.production: sk_prod_secret456

# List all keys
enever list
# API_KEY
# DATABASE_URL
```

## Commands

| Command | Description |
|---------|-------------|
| `get [KEY]` | Get all variables or a specific key |
| `set KEY=VALUE` | Set a key-value pair in `.env.local` |
| `list` | List all keys (no values) |

## Options

| Option | Description |
|--------|-------------|
| `-u, --unmask KEY` | Show raw value of a protected key |
| `--json` | Output in JSON format |
| `-q, --quiet` | Suppress non-essential output |
| `-h, --help` | Show help |
| `-v, --version` | Show version |

## Multi-File View

enever discovers and loads all `.env*` files in the current directory:

- `.env` - Base configuration
- `.env.development` - Development settings
- `.env.production` - Production settings
- `.env.staging` - Staging settings
- `.env.local` - Local overrides (should be gitignored)
- Any other `.env.*` files

All files are shown simultaneously, letting you compare values across environments at a glance.

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Key/variable not found |

## JSON Output

```bash
# Get all variables as JSON
enever get --json

# Get specific key as JSON
enever get --json API_KEY
```

## Security

- All values are masked by default (shows `****` + last 4 characters)
- No network calls - works completely offline

## License

MIT License - see [LICENSE](LICENSE) for details.
