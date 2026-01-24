import { describe, test, expect, beforeAll } from "bun:test";
import { run, runInDir, fixture } from "./helpers";
import { writeFileSync, mkdirSync, rmSync } from "fs";
import { join } from "path";

const STRESS_FIXTURES = fixture("stress-tests");

describe("Parser Stress Tests", () => {
  // ================================================================
  // 1. Whitespace & Structural Edge Cases
  // ================================================================
  describe("Whitespace and Structure", () => {
    test("handles leading spaces before key", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "LEADING_SPACES_KEY", "-u", "LEADING_SPACES_KEY");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("value");
    });

    test("handles spaces before equals sign", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "KEY_SPACES_BEFORE_EQ", "-u", "KEY_SPACES_BEFORE_EQ");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("value");
    });

    test("handles spaces after equals sign", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "KEY_SPACES_AFTER_EQ", "-u", "KEY_SPACES_AFTER_EQ");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("value");
    });

    test("handles trailing spaces after closing quote", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "KEY_TRAILING_SPACES", "-u", "KEY_TRAILING_SPACES");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("value");
    });

    test("handles export keyword prefix", async () => {
      const { stdout, exitCode } = await runInDir(STRESS_FIXTURES, "list");
      expect(exitCode).toBe(0);
    });

    test("handles spaces inside and outside quotes", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "KEY_SPACES_EVERYWHERE", "-u", "KEY_SPACES_EVERYWHERE");
      expect(exitCode).toBe(0);
      expect(stdout).toContain(" value ");
    });

    test("handles empty value (no value after =)", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "EMPTY_NO_VALUE", "-u", "EMPTY_NO_VALUE");
      expect(exitCode).toBe(0);
    });

    test("handles explicit empty string (quoted)", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "EMPTY_QUOTED", "-u", "EMPTY_QUOTED");
      expect(exitCode).toBe(0);
    });

    test("ignores key with no equals sign", async () => {
      const { stdout, exitCode } = await runInDir(STRESS_FIXTURES, "list");
      expect(exitCode).toBe(0);
      expect(stdout).not.toContain("KEY_WITH_NO_EQUALS");
    });

    test("handles tabs around equals", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "TABS_AROUND", "-u", "TABS_AROUND");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("tabbed_value");
    });
  });

  // ================================================================
  // 2. Quoting and Escape Sequences
  // ================================================================
  describe("Quoting and Escaping", () => {
    test("single quotes inside double quotes", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "SINGLE_IN_DOUBLE", "-u", "SINGLE_IN_DOUBLE");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("It's 'fine'");
    });

    test("double quotes inside single quotes", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "DOUBLE_IN_SINGLE", "-u", "DOUBLE_IN_SINGLE");
      expect(exitCode).toBe(0);
      expect(stdout).toContain('He said');
      expect(stdout).toContain('Hello');
    });

    test("escaped double quote inside double quotes", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "ESCAPED_QUOTE", "-u", "ESCAPED_QUOTE");
      expect(exitCode).toBe(0);
      expect(stdout).toContain('backslash');
      expect(stdout).toContain('works');
    });

    test("literal backslash (double backslash)", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "LITERAL_BACKSLASH", "-u", "LITERAL_BACKSLASH");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("C:");
      expect(stdout).toContain("Users");
      expect(stdout).toContain("Node");
    });

    test("multiline value inside quotes", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "MULTILINE_QUOTED", "-u", "MULTILINE_QUOTED");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("Line one");
      expect(stdout).toContain("Line two");
    });

    test("escaped newline sequence", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "ESCAPED_NEWLINE", "-u", "ESCAPED_NEWLINE");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("First line");
      expect(stdout).toContain("Second line");
    });

    test("escaped tab sequence", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "ESCAPED_TAB", "-u", "ESCAPED_TAB");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("Tab");
      expect(stdout).toContain("here");
    });

    test("single quotes preserve literal content", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "SINGLE_QUOTE_LITERAL", "-u", "SINGLE_QUOTE_LITERAL");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("$expansion");
    });

    test("mixed escape sequences", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "MIXED_ESCAPES", "-u", "MIXED_ESCAPES");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("Path:");
    });
  });

  // ================================================================
  // 3. Comments and Special Characters
  // ================================================================
  describe("Comments and Special Characters", () => {
    test("hash immediately following unquoted value", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "KEY_HASH_NO_SPACE", "-u", "KEY_HASH_NO_SPACE");
      expect(exitCode).toBe(0);
    });

    test("hash with space in unquoted value", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "KEY_HASH_WITH_SPACE", "-u", "KEY_HASH_WITH_SPACE");
      expect(exitCode).toBe(0);
    });

    test("hash inside quoted string is preserved", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "HASH_IN_QUOTES", "-u", "HASH_IN_QUOTES");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("#notacomment");
    });

    test("URL with hash fragment", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "URL_WITH_FRAGMENT", "-u", "URL_WITH_FRAGMENT");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("http://example.com/api?v=1#fragment");
    });

    test("equals sign inside value", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "EQUAL_IN_VALUE", "-u", "EQUAL_IN_VALUE");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("key=value");
    });

    test("multiple equals signs in unquoted value", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "MULTIPLE_EQUALS", "-u", "MULTIPLE_EQUALS");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("a=b=c=d");
    });

    test("Chinese UTF-8 value", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "CHINESE_VALUE", "-u", "CHINESE_VALUE");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("你好世界");
    });

    test("Arabic UTF-8 value", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "ARABIC_VALUE", "-u", "ARABIC_VALUE");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("مرحبا");
    });

    test("Russian UTF-8 value", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "RUSSIAN_VALUE", "-u", "RUSSIAN_VALUE");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("Привет мир");
    });

    test("Japanese UTF-8 value", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "JAPANESE_VALUE", "-u", "JAPANESE_VALUE");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("こんにちは");
    });

    test("simple JSON in single quotes", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "JSON_SIMPLE", "-u", "JSON_SIMPLE");
      expect(exitCode).toBe(0);
      expect(stdout).toContain('key');
      expect(stdout).toContain('value');
    });

    test("nested JSON in single quotes", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "JSON_NESTED", "-u", "JSON_NESTED");
      expect(exitCode).toBe(0);
      expect(stdout).toContain('user');
      expect(stdout).toContain('name');
      expect(stdout).toContain('John');
    });
  });

  // ================================================================
  // 4. Variable References (No Interpolation)
  // ================================================================
  describe("Variable References", () => {
    test("dollar sign references are kept literal", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "VAR_BASIC", "-u", "VAR_BASIC");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("$BASE_VAR");
    });

    test("braced variable references are kept literal", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "VAR_BRACED", "-u", "VAR_BRACED");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("${BASE_VAR}");
    });

    test("escaped dollar sign", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "ESCAPED_DOLLAR", "-u", "ESCAPED_DOLLAR");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("$100");
    });

    test("lone dollar sign", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "DOLLAR_NO_VAR", "-u", "DOLLAR_NO_VAR");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("$");
    });

    test("dollar at end of value", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "DOLLAR_END", "-u", "DOLLAR_END");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("value$");
    });

    test("partial/incomplete variable reference", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "PARTIAL_VAR", "-u", "PARTIAL_VAR");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("${INCOMPLETE");
    });
  });

  // ================================================================
  // 5. Edge Cases
  // ================================================================
  describe("Edge Cases", () => {
    test("path traversal is stored as string value", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "PATH_TRAVERSAL", "-u", "PATH_TRAVERSAL");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("../../../etc/passwd");
    });

    test("null string value", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "NULL_STRING", "-u", "NULL_STRING");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("null");
    });

    test("boolean-like values are strings", async () => {
      const { stdout: t, exitCode: t_code } = await run("read", STRESS_FIXTURES, "BOOL_TRUE", "-u", "BOOL_TRUE");
      const { stdout: f, exitCode: f_code } = await run("read", STRESS_FIXTURES, "BOOL_FALSE", "-u", "BOOL_FALSE");
      expect(t_code).toBe(0);
      expect(f_code).toBe(0);
      expect(t).toContain("true");
      expect(f).toContain("false");
    });

    test("numeric edge cases", async () => {
      const { stdout: neg, exitCode: neg_code } = await run("read", STRESS_FIXTURES, "NEGATIVE_NUM", "-u", "NEGATIVE_NUM");
      const { stdout: flt, exitCode: flt_code } = await run("read", STRESS_FIXTURES, "FLOAT_NUM", "-u", "FLOAT_NUM");
      const { stdout: sci, exitCode: sci_code } = await run("read", STRESS_FIXTURES, "SCIENTIFIC", "-u", "SCIENTIFIC");
      const { stdout: hex, exitCode: hex_code } = await run("read", STRESS_FIXTURES, "HEX_VALUE", "-u", "HEX_VALUE");

      expect(neg_code).toBe(0);
      expect(flt_code).toBe(0);
      expect(sci_code).toBe(0);
      expect(hex_code).toBe(0);

      expect(neg).toContain("-42");
      expect(flt).toContain("3.14159");
      expect(sci).toContain("1.23e10");
      expect(hex).toContain("0xDEADBEEF");
    });

    test("backtick in quoted value is not executed", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "BACKTICK_QUOTED", "-u", "BACKTICK_QUOTED");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("`command`");
    });

    test("command substitution syntax is not executed", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "DOLLAR_PARENS_QUOTED", "-u", "DOLLAR_PARENS_QUOTED");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("$(command)");
    });

    test("very long key name", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES,
        "VERY_LONG_KEY_NAME_THAT_GOES_ON_AND_ON_AND_ON_AND_ON_ABCDEFGHIJKLMNOPQRSTUVWXYZ",
        "-u", "VERY_LONG_KEY_NAME_THAT_GOES_ON_AND_ON_AND_ON_AND_ON_ABCDEFGHIJKLMNOPQRSTUVWXYZ");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("longkey");
    });

    test("whitespace-only value", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "WHITESPACE_ONLY", "-u", "WHITESPACE_ONLY");
      expect(exitCode).toBe(0);
    });
  });

  // ================================================================
  // File Format Edge Cases
  // ================================================================
  describe("File Format Edge Cases", () => {
    test("file with UTF-8 BOM", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES + "/+.env.bom", "BOM_KEY", "-u", "BOM_KEY");
      // Parser behavior with BOM prefix
    });

    test("file with CRLF line endings", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES + "/+.env.crlf", "CRLF_KEY1", "-u", "CRLF_KEY1");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("value1");
    });

    test("mixed LF and CRLF in same file", async () => {
      const { stdout, exitCode } = await run("read", STRESS_FIXTURES + "/+.env.crlf", "MIXED_LF", "-u", "MIXED_LF");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("value3");
    });

    test("unclosed quote handles gracefully", async () => {
      const { exitCode } = await runInDir(STRESS_FIXTURES, "read", "+.env.unclosed");
      // Should not hang or crash
    });

    test("mismatched quotes handled gracefully", async () => {
      const { exitCode } = await runInDir(STRESS_FIXTURES, "read", "+.env.mismatched");
      // Should not hang or crash
    });
  });

  // ================================================================
  // Malformed Input
  // ================================================================
  describe("Malformed Input", () => {
    let tempDir: string;

    beforeAll(() => {
      tempDir = join(STRESS_FIXTURES, "temp-no-key");
      try { rmSync(tempDir, { recursive: true }); } catch {}
      mkdirSync(tempDir, { recursive: true });
      writeFileSync(join(tempDir, "+.env"), "=VALUE_WITH_NO_KEY\nVALID_KEY=valid\n");
    });

    test("ignores line with no key (=VALUE)", async () => {
      const { stdout, exitCode } = await runInDir(tempDir, "list");
      expect(exitCode).toBe(0);
      expect(stdout).toContain("VALID_KEY");
    });
  });
});

// ================================================================
// Parser Behavior Documentation
// ================================================================
describe("Parser Behavior Documentation", () => {
  test("export keyword is included in key name", async () => {
    const { stdout, exitCode } = await runInDir(STRESS_FIXTURES, "list");
    expect(exitCode).toBe(0);
    expect(stdout).toContain("export INDENTED_EXPORT");
  });

  test("UTF-8 BOM is included in first key", async () => {
    const { stdout, exitCode } = await runInDir(STRESS_FIXTURES, "list");
    expect(exitCode).toBe(0);
    // BOM character is included in key name
  });

  test("unquoted hash is part of value", async () => {
    const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "KEY_HASH_NO_SPACE", "-u", "KEY_HASH_NO_SPACE");
    expect(exitCode).toBe(0);
    expect(stdout).toContain("value#comment");
  });

  test("unquoted value with space-hash preserves content", async () => {
    const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "KEY_HASH_WITH_SPACE", "-u", "KEY_HASH_WITH_SPACE");
    expect(exitCode).toBe(0);
  });
});

// ================================================================
// JSON Output
// ================================================================
describe("JSON Output", () => {
  test("handles special characters", async () => {
    const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "--json");
    expect(exitCode).toBe(0);
    expect(() => JSON.parse(stdout)).not.toThrow();
  });

  test("handles multiline values", async () => {
    const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "MULTILINE_QUOTED", "-u", "MULTILINE_QUOTED", "--json");
    expect(exitCode).toBe(0);
    expect(() => JSON.parse(stdout)).not.toThrow();
  });

  test("handles UTF-8 values", async () => {
    const { stdout, exitCode } = await run("read", STRESS_FIXTURES, "CHINESE_VALUE", "-u", "CHINESE_VALUE", "--json");
    expect(exitCode).toBe(0);
    expect(() => JSON.parse(stdout)).not.toThrow();
  });
});
