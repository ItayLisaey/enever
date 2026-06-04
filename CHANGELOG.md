# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-06-04

Agent-capability release: every command is now scriptable and pipeable with
machine-readable output and structured errors.

### Added

- `exec` (alias `run`) — run a command with the real env vars injected into its
  environment (`enever exec -- npm run dev`). Values are passed to the child
  process only and never printed; the child's exit code is propagated (`127`
  command not found, `126` not executable).
- `copy` (alias `cp`) — copy env vars from a source file/directory into a
  destination `.env` file (`enever copy . .env.staging [KEY ...]`). Real values
  are copied but never printed; existing destination keys are preserved unless
  `--force`. Reports `copied`/`skipped`/`not_found` in `--json`.
- `schema` command — machine-readable JSON describing every command, flag, and
  exit code. The primary affordance for AI agents to self-discover the CLI.
- `--json` is now honored by **every** command (`list`, `diff`, `write`,
  `delete`, `version`), not just `read`. Each has a documented, stable shape.
- Structured error envelopes on stderr in `--json` mode:
  `{"error":{"code","message","hint"}}` with stable string error codes
  (`USAGE`, `KEY_NOT_FOUND`, `KEY_EXISTS`, `FILE_NOT_FOUND`, `LOAD_FAILED`, …).
- `-n, --dry-run` for `write` and `delete` — preview changes without modifying files.
- `-y, --yes` as an alias for `--force`.
- `--no-color` accepted as a documented no-op for agent/CI compatibility.
- Exit code `64` (usage error) for invalid arguments, surfaced in `schema`.
- `AGENTS.md` and an Agent Skill describing safe `enever` usage.

### Changed

- Migrated the codebase to **Zig 0.16** (`minimum_zig_version` is now `0.16.0`).
  Adopts the new I/O model: `main(init: std.process.Init)`, `std.Io` threaded
  through file/process operations, and `std.Io.Writer` for all output.

### Fixed

- Use-after-free crash when piping `KEY=value` lines to `write` via stdin
  (the stdin buffer was freed before the parsed slices were consumed).

## [0.3.0] - 2025-01-25

### Changed

- Renamed `get` command to `read` for clarity
- Renamed `set` command to `write` for clarity

### Added

- `delete` command to remove keys from env files
- `diff` command to compare two .env files
- `--force` flag for write command to overwrite existing keys
- `-f, --file` flag for write/delete to target specific files
- Exit code 3 for key already exists (write without --force)

## [0.2.1] - 2025-01-23

### Fixed

- Fixed parsing of multiline quoted values (e.g., JSON strings spanning multiple lines)
- Properly handle escape sequences (`\n`, `\t`, `\\`, `\"`, `\'`) within quoted values
- Service account keys and other multiline JSON values now parse correctly

## [0.2.0] - 2025-01-23

### Added

- Initial release
- Core commands:
  - `get [KEY]` - Retrieve environment variables (all or specific key)
  - `set KEY=VALUE` - Set key-value pairs in `.env.local`
  - `list` - List all available keys without values
  - `help` - Show help message
  - `version` - Show version
- Security features:
  - All values masked by default (shows `****` + last 4 chars)
  - `-u/--unmask` flag for explicit value revelation
- Multi-file view:
  - Discovers and loads all `.env*` files in current directory
  - Shows values from each file side-by-side
- Output formats:
  - TOON format (human-readable structured output)
  - JSON output with `--json` flag
  - Quiet mode with `-q/--quiet` flag
- Exit codes:
  - 0 = Success
  - 1 = General error
  - 2 = Key/variable not found
- Distribution:
  - Pre-built binaries for Linux (x64, arm64), macOS (x64, arm64), Windows (x64)
  - SHA256 checksums for all releases

[Unreleased]: https://github.com/itaylisaey/enever/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/itaylisaey/enever/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/itaylisaey/enever/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/itaylisaey/enever/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/itaylisaey/enever/releases/tag/v0.2.0
