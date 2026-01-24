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

    test("reads specific key", async () => {
      const { stdout, exitCode } = await run("read", fixture("basic"), "API_KEY");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("API_KEY");
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

  describe("validate", () => {
    test("validates a valid env directory", async () => {
      const { exitCode } = await run("validate", fixture("basic"));
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
});
