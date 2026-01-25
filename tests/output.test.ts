import { describe, test, expect } from "bun:test";
import { run, runInDir, fixture } from "./helpers";

describe("Output formats", () => {
  describe("JSON output", () => {
    test("outputs valid JSON with --json flag", async () => {
      const { stdout, exitCode } = await run("read", fixture("basic"), "--json");
      expect(exitCode).toBe(0);
      expect(() => JSON.parse(stdout)).not.toThrow();
    });

    test("JSON contains all keys", async () => {
      const { stdout, exitCode } = await run("read", fixture("basic"), "--json");
      expect(exitCode).toBe(0);
      const data = JSON.parse(stdout);
      expect(data).toHaveProperty("DATABASE_URL");
      expect(data).toHaveProperty("API_KEY");
      expect(data).toHaveProperty("PORT");
    });

    test("JSON values are masked by default", async () => {
      const { stdout, exitCode } = await run("read", fixture("basic"), "--json");
      expect(exitCode).toBe(0);
      const data = JSON.parse(stdout);
      expect(data.API_KEY[0].value).toContain("****");
    });

    test("JSON values can be unmasked", async () => {
      const { stdout, exitCode } = await run("read", fixture("basic"), "--json", "-u", "API_KEY");
      expect(exitCode).toBe(0);
      const data = JSON.parse(stdout);
      expect(data.API_KEY[0].value).toBe("sk-1234567890abcdef");
    });
  });

  describe("list output", () => {
    test("lists only keys (no values)", async () => {
      const { stdout, exitCode } = await runInDir(fixture("basic"), "list");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("DATABASE_URL");
      expect(stdout).not.toContain("postgres://");
    });
  });

  describe("read output", () => {
    test("shows key-value pairs", async () => {
      const { stdout, exitCode } = await run("read", fixture("basic"));
      expect(exitCode).toBe(0);
      expect(stdout).toContain("DATABASE_URL");
      expect(stdout).toContain("API_KEY");
      expect(stdout).toContain("****");
    });

    test("value is masked by default", async () => {
      const { stdout, exitCode } = await run("read", fixture("basic"), "API_KEY");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("****");
    });

    test("unmasked value is shown with -u flag", async () => {
      const { stdout, exitCode } = await run("read", fixture("basic"), "-u", "PORT");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("3000");
    });
  });

  describe("quiet mode", () => {
    test("-q flag suppresses extra output", async () => {
      const { exitCode } = await run("read", fixture("basic"), "-q");
      expect(exitCode).toBe(0);
    });
  });

  describe("special characters in output", () => {
    test("handles JSON with special characters", async () => {
      const { stdout, exitCode } = await run("read", fixture("edge-cases"), "--json");
      expect(exitCode).toBe(0);
      expect(() => JSON.parse(stdout)).not.toThrow();
    });

    test("handles unicode in JSON output", async () => {
      const { stdout, exitCode } = await run("read", fixture("edge-cases"), "EMOJI", "-u", "EMOJI", "--json");
      expect(exitCode).toBe(0);
      expect(() => JSON.parse(stdout)).not.toThrow();
    });
  });
});
