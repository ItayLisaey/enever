# AGENTS.md

Guidance for AI agents working in the `enever` repository.

`enever` is a secure environment-variable CLI written in Zig. It is itself
designed to be driven by agents — run `enever schema` to see the full
machine-readable interface.

## Toolchain

Requires **Zig 0.16.0+** (see `minimum_zig_version` in `build.zig.zon`). The
codebase uses the 0.16 I/O model: `main(init: std.process.Init)`, `std.Io`
threaded through file/process operations, and `std.Io.Writer` for output.

## Build

```bash
zig build -Doptimize=ReleaseSafe   # binary -> zig-out/bin/enever
```

## Test

Tests need a freshly built binary at `zig-out/bin/enever`.

```bash
zig build && bun test    # full suite (npm test)
bun test                 # behavior tests only, against the current binary
zig test src/main.zig    # Zig unit tests (test {} blocks)
```

After changing any `src/*.zig`, rebuild the binary before running `bun test`.

## Layout

- `src/main.zig` — entry point, allocator, top-level error handling.
- `src/cli.zig` — argument parsing, command dispatch, exit codes, schema.
- `src/output.zig` — output formatting (TOON, JSON, list).
- `src/env-parser.zig` — `.env` discovery and parsing.
- `src/masking.zig` — value masking (security-first default).
- `tests/*.test.ts` — behavior tests (Bun) that spawn the built binary.
- `tests/agent.test.ts` — agent-surface tests (schema, `--json`, errors, dry-run).

## Conventions

- Files are kebab-case.
- Keep output **deterministic**: sort keys, never emit ANSI color, no spinners.
- `--json` must be honored by every command; errors in `--json` mode go to
  **stderr** as `{"error":{"code","message","hint"}}` and stdout stays clean.
- Mutating commands (`write`, `delete`) must support `--dry-run`.
- Update `enever schema`, `--help`, and the README together when commands,
  flags, or exit codes change. Bump the version in `src/cli.zig` and
  `package.json` together.
- Never read `.env` files directly in examples or docs — use `enever`.
