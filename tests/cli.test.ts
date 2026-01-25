import { describe, test, expect } from "bun:test";
import { run, runInDir, fixture } from "./helpers";

describe("CLI commands", () => {
  describe("help", () => {
    test("shows help with --help flag", async () => {
      const { stdout, exitCode } = await run("--help");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("Usage:");
    });

    test("shows help with help command", async () => {
      const { stdout, exitCode } = await run("help");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("Usage:");
    });

    test("shows help with no arguments", async () => {
      const { stdout, exitCode } = await run();
      expect(exitCode).toBe(0);
      expect(stdout).toContain("Usage:");
    });
  });

  describe("version", () => {
    test("shows version with --version flag", async () => {
      const { stdout, exitCode } = await run("--version");
      expect(exitCode).toBe(0);
    });

    test("shows version with version command", async () => {
      const { stdout, exitCode } = await run("version");
      expect(exitCode).toBe(0);
    });
  });

  describe("read", () => {
    test("reads all env vars from directory", async () => {
      const { stdout, exitCode } = await run("read", fixture("basic"));
      expect(exitCode).toBe(0);
      expect(stdout).toContain("DATABASE_URL");
      expect(stdout).toContain("API_KEY");
      expect(stdout).toContain("SECRET_KEY");
      expect(stdout).toContain("DEBUG");
      expect(stdout).toContain("PORT");
    });

    test("reads specific key from current directory", async () => {
      const { stdout, exitCode } = await runInDir(fixture("basic"), "read", "API_KEY");
      expect(exitCode).toBe(0);
      // Single key output format is "<file>: <masked_value>"
      expect(stdout).toContain("+.env:");
      expect(stdout).toContain("****");
      // Should only show one file entry, not multiple keys
      expect(stdout).not.toContain("DATABASE_URL");
      expect(stdout).not.toContain("SECRET_KEY");
    });

    test("values are masked by default", async () => {
      const { stdout, exitCode } = await run("read", fixture("basic"));
      expect(exitCode).toBe(0);
      expect(stdout).toContain("****");
      expect(stdout).not.toContain("sk-1234567890abcdef");
    });

    test("unmask specific key with -u", async () => {
      const { stdout, exitCode } = await run("read", fixture("basic"), "-u", "API_KEY");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("sk-1234567890abcdef");
    });

    test("handles empty directory", async () => {
      const { stdout, exitCode } = await run("read", fixture("empty-dir"));
      expect(exitCode).toBe(0);
    });
  });

  describe("list", () => {
    test("lists all keys", async () => {
      const { stdout, exitCode } = await runInDir(fixture("basic"), "list");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("DATABASE_URL");
      expect(stdout).toContain("API_KEY");
    });
  });

  describe("diff", () => {
    test("shows differences between files", async () => {
      const { stdout, exitCode } = await run(
        "diff",
        fixture("overrides/+.env"),
        fixture("overrides/+.env.development")
      );
      expect(exitCode).toBe(0);
    });
  });

  describe("file not found", () => {
    test("returns error for missing directory", async () => {
      const { exitCode } = await run("read", "/nonexistent/path");
      expect(exitCode).not.toBe(0);
    });
  });

  describe("json output", () => {
    test("outputs valid JSON with --json flag", async () => {
      const { stdout, exitCode } = await run("read", fixture("basic"), "--json");
      expect(exitCode).toBe(0);
      expect(() => JSON.parse(stdout)).not.toThrow();
    });

    test("JSON contains all keys", async () => {
      const { stdout, exitCode } = await run("read", fixture("basic"), "--json");
      expect(exitCode).toBe(0);
      const data = JSON.parse(stdout);
      expect(data).toHaveProperty("API_KEY");
      expect(data).toHaveProperty("DATABASE_URL");
      expect(data).toHaveProperty("PORT");
    });
  });

  describe("quiet mode", () => {
    test("accepts -q for quiet mode", async () => {
      const { exitCode } = await run("read", fixture("basic"), "-q");
      expect(exitCode).toBe(0);
    });
  });

  describe("path vs key detection", () => {
    test("key ending in .env is treated as key lookup, not path", async () => {
      // A key like MY_KEY.env should be treated as a key, not a path
      const { stderr, exitCode } = await runInDir(fixture("basic"), "read", "MY_KEY.env");
      // Should return "Key not found" (exit code 2), not a path error
      expect(exitCode).toBe(2);
      expect(stderr).toContain("Key not found");
    });

    test("key containing .env. is treated as key lookup, not path", async () => {
      const { stderr, exitCode } = await runInDir(fixture("basic"), "read", "CONFIG.env.backup");
      expect(exitCode).toBe(2);
      expect(stderr).toContain("Key not found");
    });

    test("actual .env file path is treated as path", async () => {
      const { stdout, exitCode } = await run("read", fixture("basic"));
      expect(exitCode).toBe(0);
      expect(stdout).toContain("API_KEY");
    });
  });

  describe("cross-platform path handling", () => {
    test("reads specific key from directory path with native separators", async () => {
      // This test verifies that paths with platform-native separators work correctly
      // On Windows, fixture() returns paths with backslashes (D:\a\...\fixtures\basic)
      // On Unix, it returns paths with forward slashes (/home/.../fixtures/basic)
      const { stdout, exitCode } = await run("read", fixture("basic"), "API_KEY", "-u", "API_KEY");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("sk-1234567890abcdef");
    });

    test("reads all keys from nested directory path", async () => {
      // Test that directory iteration works with platform-native path separators
      const { stdout, exitCode } = await run("read", fixture("basic"));
      expect(exitCode).toBe(0);
      expect(stdout).toContain("API_KEY");
      expect(stdout).toContain("DATABASE_URL");
      expect(stdout).toContain("PORT");
    });

    test("diff command works with platform-native paths", async () => {
      // Ensure diff command handles paths correctly across platforms
      const { exitCode } = await run(
        "diff",
        fixture("overrides/+.env"),
        fixture("overrides/+.env.development")
      );
      expect(exitCode).toBe(0);
    });

    test("path with forward slash is detected as path, not key", async () => {
      // Non-existent path with forward slash should be treated as path (error), not key lookup
      const { stderr, exitCode } = await run("read", "/nonexistent/path/to/dir");
      // Should get a path error (exit code 1), not "key not found" (exit code 2)
      expect(exitCode).toBe(1);
      expect(stderr).toContain("Error");
    });

    test("path with backslash is detected as path, not key", async () => {
      // Non-existent path with backslash should be treated as path (error), not key lookup
      // This is critical for Windows path handling
      const { stderr, exitCode } = await run("read", "C:\\nonexistent\\path\\to\\dir");
      // Should get a path error (exit code 1), not "key not found" (exit code 2)
      expect(exitCode).toBe(1);
      expect(stderr).toContain("Error");
    });

    test("path starting with dot is detected as path, not key", async () => {
      // Paths starting with . should be treated as paths
      const { stderr, exitCode } = await run("read", "./nonexistent/path");
      expect(exitCode).toBe(1);
      expect(stderr).toContain("Error");
    });
  });
});
