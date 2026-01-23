# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/itaylisaey/enever/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/itaylisaey/enever/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/itaylisaey/enever/releases/tag/v0.2.0
