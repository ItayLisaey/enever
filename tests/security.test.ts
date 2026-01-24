import { describe, test, expect } from "bun:test";
import { run, fixture } from "./helpers";

describe("Security and masking", () => {
  describe("default masking", () => {
    test("all values are masked by default", async () => {
      const { stdout, exitCode } = await run("read", fixture("basic"));
      expect(exitCode).toBe(0);
      expect(stdout).not.toContain("sk-1234567890abcdef");
      expect(stdout).not.toContain("super_secret_value_123");
      expect(stdout).not.toContain("postgres://user:password");
    });

    test("read command masks by default", async () => {
      const { stdout, exitCode } = await run("read", fixture("basic"), "API_KEY");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("****");
      expect(stdout).not.toContain("sk-1234567890abcdef");
    });

    test("JSON output masks by default", async () => {
      const { stdout, exitCode } = await run("read", fixture("basic"), "--json");
      expect(exitCode).toBe(0);
      const data = JSON.parse(stdout);
      expect(data.API_KEY[0].value).toContain("****");
      expect(data.SECRET_KEY[0].value).toContain("****");
    });
  });

  describe("selective unmasking", () => {
    test("-u flag unmasks specific key", async () => {
      const { stdout, exitCode } = await run("read", fixture("basic"), "-u", "API_KEY");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("sk-1234567890abcdef");
    });

    test("multiple -u flags unmask multiple keys", async () => {
      const { stdout, exitCode } = await run("read", fixture("basic"), "--json", "-u", "API_KEY", "-u", "PORT");
      expect(exitCode).toBe(0);
      const data = JSON.parse(stdout);
      expect(data.API_KEY[0].value).toBe("sk-1234567890abcdef");
      expect(data.PORT[0].value).toBe("3000");
      expect(data.SECRET_KEY[0].value).toContain("****");
    });

    test("other values remain masked when unmasking one", async () => {
      const { stdout, exitCode } = await run("read", fixture("basic"), "--json", "-u", "PORT");
      expect(exitCode).toBe(0);
      const data = JSON.parse(stdout);
      expect(data.PORT[0].value).toBe("3000");
      expect(data.API_KEY[0].value).toContain("****");
      expect(data.SECRET_KEY[0].value).toContain("****");
    });
  });

  describe("mask format", () => {
    test("short values show only ****", async () => {
      const { stdout, exitCode } = await run("read", fixture("basic"), "PORT");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("****");
    });

    test("longer values show **** plus last 4 chars", async () => {
      const { stdout, exitCode } = await run("read", fixture("basic"), "API_KEY");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("****");
      expect(stdout).toContain("cdef");
    });
  });

  describe("sensitive patterns", () => {
    test("database URLs are masked", async () => {
      const { stdout, exitCode } = await run("read", fixture("basic"), "DATABASE_URL");
      expect(exitCode).toBe(0);
      expect(stdout).not.toContain("password");
    });

    test("API keys are masked", async () => {
      const { stdout, exitCode } = await run("read", fixture("basic"), "API_KEY");
      expect(exitCode).toBe(0);
      expect(stdout).not.toContain("sk-1234567890abcdef");
    });

    test("secrets are masked", async () => {
      const { stdout, exitCode } = await run("read", fixture("basic"), "SECRET_KEY");
      expect(exitCode).toBe(0);
      expect(stdout).not.toContain("super_secret");
    });
  });

  describe("edge cases", () => {
    test("empty values are handled", async () => {
      const { exitCode } = await run("read", fixture("edge-cases"), "EMPTY_VALUE");
      expect(exitCode).toBe(0);
    });

    test("quoted values are masked correctly", async () => {
      const { stdout, exitCode } = await run("read", fixture("quotes"), "DOUBLE_QUOTED");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("****");
    });
  });
});
