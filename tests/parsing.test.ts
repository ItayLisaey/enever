import { describe, test, expect } from "bun:test";
import { run, runInDir, fixture } from "./helpers";

describe("Env parsing", () => {
  describe("basic parsing", () => {
    test("parses simple key=value pairs", async () => {
      const { stdout, exitCode } = await run("read", fixture("basic"), "PORT", "-u", "PORT");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("3000");
    });

    test("parses all keys from basic file", async () => {
      const { stdout, exitCode } = await runInDir(fixture("basic"), "list");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("DATABASE_URL");
      expect(stdout).toContain("API_KEY");
      expect(stdout).toContain("SECRET_KEY");
      expect(stdout).toContain("DEBUG");
      expect(stdout).toContain("PORT");
    });
  });

  describe("quoted values", () => {
    test("parses double quoted values", async () => {
      const { stdout, exitCode } = await run("read", fixture("quotes"), "DOUBLE_QUOTED", "-u", "DOUBLE_QUOTED");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("hello world");
    });

    test("parses single quoted values", async () => {
      const { stdout, exitCode } = await run("read", fixture("quotes"), "SINGLE_QUOTED", "-u", "SINGLE_QUOTED");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("hello world");
    });

    test("preserves spaces in quoted values", async () => {
      const { stdout, exitCode } = await run("read", fixture("quotes"), "DOUBLE_WITH_SPACES", "-u", "DOUBLE_WITH_SPACES");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("  spaces around  ");
    });

    test("parses nested quotes", async () => {
      const { stdout, exitCode } = await run("read", fixture("quotes"), "NESTED_QUOTES", "-u", "NESTED_QUOTES");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("He said 'hello' to me");
    });

    test("handles empty quoted values", async () => {
      const { stdout, exitCode } = await run("read", fixture("quotes"), "EMPTY_DOUBLE", "-u", "EMPTY_DOUBLE");
      expect(exitCode).toBe(0);
    });
  });

  describe("multiline values", () => {
    test("parses multiline JSON", async () => {
      const { stdout, exitCode } = await run("read", fixture("multiline"), "GOOGLE_CREDENTIALS", "-u", "GOOGLE_CREDENTIALS");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("service_account");
      expect(stdout).toContain("project_id");
    });

    test("parses escaped newlines", async () => {
      const { stdout, exitCode } = await run("read", fixture("multiline"), "MULTILINE_ESCAPED", "-u", "MULTILINE_ESCAPED");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("line1");
    });
  });

  describe("edge cases", () => {
    test("parses unicode and emoji", async () => {
      const { stdout, exitCode } = await run("read", fixture("edge-cases"), "EMOJI", "-u", "EMOJI");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("Hello");
      expect(stdout).toContain("World");
    });

    test("parses URLs with special characters", async () => {
      const { stdout, exitCode } = await run("read", fixture("edge-cases"), "DATABASE_URL", "-u", "DATABASE_URL");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("postgres://");
      expect(stdout).toContain("sslmode=require");
    });

    test("parses values with equals signs", async () => {
      const { stdout, exitCode } = await run("read", fixture("edge-cases"), "CONNECTION_STRING", "-u", "CONNECTION_STRING");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("Server=localhost");
      expect(stdout).toContain("Password=secret=123");
    });

    test("parses hash inside quotes (not as comment)", async () => {
      const { stdout, exitCode } = await run("read", fixture("edge-cases"), "COLOR", "-u", "COLOR");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("#ff0000");
    });

    test("parses keys with hyphens", async () => {
      const { stdout, exitCode } = await run("read", fixture("edge-cases"), "MY-VAR", "-u", "MY-VAR");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("value-with-hyphen");
    });

    test("parses keys with dots", async () => {
      const { stdout, exitCode } = await run("read", fixture("edge-cases"), "MY.VAR", "-u", "MY.VAR");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("value.with.dot");
    });

    test("handles empty values", async () => {
      const { stdout, exitCode } = await run("read", fixture("edge-cases"), "EMPTY_VALUE", "-u", "EMPTY_VALUE");
      expect(exitCode).toBe(0);
    });
  });

  describe("comments and whitespace", () => {
    test("ignores comment lines", async () => {
      const { stdout, exitCode } = await runInDir(fixture("comments"), "list");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("KEY1");
      expect(stdout).toContain("KEY2");
      expect(stdout).toContain("KEY3");
      expect(stdout).not.toContain("#");
    });
  });

  describe("empty file", () => {
    test("handles empty file gracefully", async () => {
      const { stdout, exitCode } = await runInDir(fixture("empty-dir"), "list");
      expect(exitCode).toBe(0);
    });
  });
});
