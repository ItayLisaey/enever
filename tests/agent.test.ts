import { describe, test, expect } from "bun:test";
import { writeFileSync, readFileSync, rmSync } from "fs";
import { join } from "path";
import { run, runInDir, runWithInput, fixture, tempDir } from "./helpers";

// Tests covering the agent-facing surface: machine-readable schema, --json on
// every command, structured errors, dry-run, and consistent exit codes.

describe("schema (introspection)", () => {
  test("emits valid JSON describing the CLI", async () => {
    const { stdout, exitCode } = await run("schema");
    expect(exitCode).toBe(0);
    const schema = JSON.parse(stdout);
    expect(schema.name).toBe("enever");
    expect(typeof schema.version).toBe("string");
    const commands = schema.commands.map((c: { name: string }) => c.name);
    expect(commands).toContain("read");
    expect(commands).toContain("write");
    expect(commands).toContain("delete");
    expect(commands).toContain("diff");
    expect(commands).toContain("list");
    expect(commands).toContain("schema");
  });

  test("documents exit codes and the error envelope", async () => {
    const { stdout } = await run("schema");
    const schema = JSON.parse(stdout);
    const codes = schema.exit_codes.map((c: { code: number }) => c.code);
    expect(codes).toEqual(expect.arrayContaining([0, 1, 2, 3, 64]));
    expect(schema.error_envelope.error).toHaveProperty("code");
    expect(schema.error_envelope.error).toHaveProperty("message");
  });

  test("schema version matches `version` command", async () => {
    const schema = JSON.parse((await run("schema")).stdout);
    const ver = JSON.parse((await run("version", "--json")).stdout);
    expect(schema.version).toBe(ver.version);
  });
});

describe("--json across commands", () => {
  test("list --json returns a keys array", async () => {
    const { stdout, exitCode } = await runInDir(fixture("basic"), "list", "--json");
    expect(exitCode).toBe(0);
    const data = JSON.parse(stdout);
    expect(Array.isArray(data.keys)).toBe(true);
    expect(data.keys).toContain("API_KEY");
  });

  test("diff --json returns classified entries", async () => {
    const dir = tempDir();
    try {
      writeFileSync(join(dir, "a.env"), "A=1\nB=2\n");
      writeFileSync(join(dir, "b.env"), "B=9\nC=3\n");
      const { stdout, exitCode } = await run("diff", join(dir, "a.env"), join(dir, "b.env"), "--json");
      expect(exitCode).toBe(0);
      const data = JSON.parse(stdout);
      const byKey = Object.fromEntries(data.diff.map((d: any) => [d.key, d.status]));
      expect(byKey).toEqual({ A: "removed", B: "changed", C: "added" });
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("version --json returns name and version", async () => {
    const { stdout } = await run("version", "--json");
    const data = JSON.parse(stdout);
    expect(data.name).toBe("enever");
  });
});

describe("structured errors", () => {
  test("missing key emits KEY_NOT_FOUND envelope on stderr", async () => {
    const { stderr, stdout, exitCode } = await runInDir(fixture("basic"), "read", "NOPE", "--json");
    expect(exitCode).toBe(2);
    expect(stdout).toBe(""); // errors never pollute stdout
    const err = JSON.parse(stderr);
    expect(err.error.code).toBe("KEY_NOT_FOUND");
  });

  test("unknown flag exits 64 with USAGE code", async () => {
    const { stderr, exitCode } = await run("list", "--bogus", "--json");
    expect(exitCode).toBe(64);
    expect(JSON.parse(stderr).error.code).toBe("USAGE");
  });
});

describe("write/delete (JSON + dry-run)", () => {
  test("write --json reports written keys without touching file in dry-run", async () => {
    const dir = tempDir();
    try {
      const dry = await runWithInput("", dir, "write", "FOO=bar", "--dry-run", "--json");
      expect(dry.exitCode).toBe(0);
      expect(JSON.parse(dry.stdout)).toMatchObject({ dry_run: true });
      // Nothing should have been written
      const list = await runInDir(dir, "list", "--json");
      expect(JSON.parse(list.stdout).keys).not.toContain("FOO");

      const real = await runWithInput("", dir, "write", "FOO=bar", "--json");
      expect(real.exitCode).toBe(0);
      expect(JSON.parse(real.stdout)).toMatchObject({ dry_run: false });
      const list2 = await runInDir(dir, "list", "--json");
      expect(JSON.parse(list2.stdout).keys).toContain("FOO");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("write existing key without --force exits 3 with KEY_EXISTS", async () => {
    const dir = tempDir();
    try {
      await runWithInput("", dir, "write", "K=1", "--json");
      const again = await runWithInput("", dir, "write", "K=2", "--json");
      expect(again.exitCode).toBe(3);
      const err = JSON.parse(again.stderr);
      expect(err.error.code).toBe("KEY_EXISTS");
      expect(err.error.keys).toContain("K");
      // --force overwrites
      const forced = await runWithInput("", dir, "write", "K=2", "--force", "--json");
      expect(forced.exitCode).toBe(0);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("write reads KEY=value pairs from stdin", async () => {
    const dir = tempDir();
    try {
      const res = await runWithInput("A=1\nB=2\n", dir, "write", "--json");
      expect(res.exitCode).toBe(0);
      const keys = JSON.parse(res.stdout).written.map((w: any) => w.key);
      expect(keys).toEqual(["A", "B"]);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("delete --json reports deleted and not_found keys", async () => {
    const dir = tempDir();
    try {
      await runWithInput("", dir, "write", "X=1", "Y=2", "--json");
      const res = await runInDir(dir, "delete", "X", "MISSING", "--json");
      expect(res.exitCode).toBe(0);
      const data = JSON.parse(res.stdout);
      expect(data.deleted).toContain("X");
      expect(data.not_found).toContain("MISSING");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

describe("copy (move env vars between files)", () => {
  // Source dir where .env.local overrides .env, so precedence is observable.
  function srcDir(): string {
    const dir = tempDir();
    writeFileSync(join(dir, ".env"), "API_KEY=base_secret\nDB_URL=postgres://x\nPORT=3000\n");
    writeFileSync(join(dir, ".env.local"), "API_KEY=local_override\n");
    return dir;
  }

  test("copies all keys into a new destination file", async () => {
    const dir = srcDir();
    try {
      const res = await runInDir(dir, "copy", ".", "out.env", "--json");
      expect(res.exitCode).toBe(0);
      const data = JSON.parse(res.stdout);
      expect(data.copied.sort()).toEqual(["API_KEY", "DB_URL", "PORT"]);
      expect(data.to).toBe("out.env");
      const written = readFileSync(join(dir, "out.env"), "utf8");
      expect(written).toContain("DB_URL=postgres://x");
      // Highest-precedence file wins: .env.local overrides .env
      expect(written).toContain("API_KEY=local_override");
      expect(written).not.toContain("API_KEY=base_secret");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("copies only the requested keys and reports not_found", async () => {
    const dir = srcDir();
    try {
      const res = await runInDir(dir, "copy", ".", "out.env", "PORT", "NOPE", "--json");
      expect(res.exitCode).toBe(0);
      const data = JSON.parse(res.stdout);
      expect(data.copied).toEqual(["PORT"]);
      expect(data.not_found).toEqual(["NOPE"]);
      const written = readFileSync(join(dir, "out.env"), "utf8");
      expect(written).toContain("PORT=3000");
      expect(written).not.toContain("API_KEY");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("preserves existing destination keys unless --force", async () => {
    const dir = srcDir();
    try {
      writeFileSync(join(dir, "dest.env"), "DB_URL=KEEP_ME\n");
      const res = await runInDir(dir, "copy", ".", "dest.env", "DB_URL", "--json");
      expect(res.exitCode).toBe(0);
      expect(JSON.parse(res.stdout).skipped).toEqual(["DB_URL"]);
      expect(readFileSync(join(dir, "dest.env"), "utf8")).toContain("DB_URL=KEEP_ME");

      const forced = await runInDir(dir, "copy", ".", "dest.env", "DB_URL", "--force", "--json");
      expect(JSON.parse(forced.stdout).copied).toEqual(["DB_URL"]);
      expect(readFileSync(join(dir, "dest.env"), "utf8")).toContain("DB_URL=postgres://x");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("--dry-run writes nothing", async () => {
    const dir = srcDir();
    try {
      const res = await runInDir(dir, "copy", ".", "out.env", "--dry-run", "--json");
      expect(JSON.parse(res.stdout).dry_run).toBe(true);
      expect(() => readFileSync(join(dir, "out.env"), "utf8")).toThrow();
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("copy from a single source file (not a directory)", async () => {
    const dir = srcDir();
    try {
      const res = await runInDir(dir, "copy", ".env", "out.env", "--json");
      expect(res.exitCode).toBe(0);
      // Source is just .env, so API_KEY is the base value (no .env.local merge)
      expect(readFileSync(join(dir, "out.env"), "utf8")).toContain("API_KEY=base_secret");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("`cp` alias works", async () => {
    const dir = srcDir();
    try {
      const res = await runInDir(dir, "cp", ".", "out.env", "PORT", "--json");
      expect(res.exitCode).toBe(0);
      expect(JSON.parse(res.stdout).copied).toEqual(["PORT"]);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("missing destination is a usage error (exit 64)", async () => {
    const dir = srcDir();
    try {
      const res = await runInDir(dir, "copy", ".", "--json");
      expect(res.exitCode).toBe(64);
      expect(JSON.parse(res.stderr).error.code).toBe("USAGE");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("schema advertises copy with its cp alias", async () => {
    const schema = JSON.parse((await run("schema")).stdout);
    const copy = schema.commands.find((c: { name: string }) => c.name === "copy");
    expect(copy).toBeDefined();
    expect(copy.aliases).toContain("cp");
  });
});

describe("exec (inject secrets into a command)", () => {
  function withEnv(): string {
    const dir = tempDir();
    writeFileSync(join(dir, ".env"), "API_KEY=base_secret\nDB_URL=postgres://base\n");
    writeFileSync(join(dir, ".env.local"), "API_KEY=local_override\n");
    return dir;
  }

  test("injects real env values into the child process", async () => {
    const dir = withEnv();
    try {
      const { stdout, exitCode } = await runInDir(dir, "exec", "-q", "--", "sh", "-c", "printf %s \"$DB_URL\"");
      expect(exitCode).toBe(0);
      expect(stdout).toBe("postgres://base");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test(".env.local overrides .env for the child", async () => {
    const dir = withEnv();
    try {
      const { stdout } = await runInDir(dir, "exec", "-q", "--", "sh", "-c", "printf %s \"$API_KEY\"");
      expect(stdout).toBe("local_override");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("propagates the child's exit code", async () => {
    const dir = withEnv();
    try {
      const { exitCode } = await runInDir(dir, "exec", "--", "sh", "-c", "exit 7");
      expect(exitCode).toBe(7);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("returns 127 for a command that does not exist", async () => {
    const dir = withEnv();
    try {
      const { exitCode } = await runInDir(dir, "exec", "--", "this_command_does_not_exist_xyz");
      expect(exitCode).toBe(127);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("does not print secret values in its own output", async () => {
    const dir = withEnv();
    try {
      const { stdout, stderr } = await runInDir(dir, "exec", "--", "sh", "-c", "true");
      // The status note may mention a count and the command, never a value.
      expect(stdout).not.toContain("base_secret");
      expect(stdout).not.toContain("local_override");
      expect(stderr).not.toContain("base_secret");
      expect(stderr).not.toContain("local_override");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("schema advertises exec", async () => {
    const schema = JSON.parse((await run("schema")).stdout);
    const names = schema.commands.map((c: { name: string }) => c.name);
    expect(names).toContain("exec");
  });
});

describe("compatibility flags", () => {
  test("--no-color is accepted as a no-op", async () => {
    const { exitCode } = await runInDir(fixture("basic"), "list", "--no-color");
    expect(exitCode).toBe(0);
  });
});
