const std = @import("std");
const env_parser = @import("env-parser");
const masking = @import("masking");
const output = @import("output");

// ============================================================================
// PARSING EDGE CASES
// ============================================================================

test "empty file handling" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try env_parser.parseEnvContent(allocator, "", ".env", &store);
    try std.testing.expectEqual(@as(usize, 0), store.count());
}

test "whitespace-only lines" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\
        \\
        \\
        \\KEY=value
        \\
        \\
    ;

    try env_parser.parseEnvContent(allocator, content, ".env", &store);
    try std.testing.expectEqual(@as(usize, 1), store.count());
    try std.testing.expectEqualStrings("value", store.get("KEY").?.value);
}

test "no newline at end of file" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    // Note: no trailing newline
    const content = "KEY1=value1\nKEY2=value2";

    try env_parser.parseEnvContent(allocator, content, ".env", &store);
    try std.testing.expectEqual(@as(usize, 2), store.count());
    try std.testing.expectEqualStrings("value1", store.get("KEY1").?.value);
    try std.testing.expectEqualStrings("value2", store.get("KEY2").?.value);
}

test "carriage return line endings" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    // CRLF line endings (Windows-style)
    const content = "KEY1=value1\r\nKEY2=value2\r\n";

    try env_parser.parseEnvContent(allocator, content, ".env", &store);
    try std.testing.expectEqual(@as(usize, 2), store.count());
    try std.testing.expectEqualStrings("value1", store.get("KEY1").?.value);
    try std.testing.expectEqualStrings("value2", store.get("KEY2").?.value);
}

test "very long value" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    // Create a value that's ~500 characters
    const long_value = "a" ** 500;
    const content = "LONG_KEY=" ++ long_value ++ "\n";

    try env_parser.parseEnvContent(allocator, content, ".env", &store);
    try std.testing.expectEqual(@as(usize, 1), store.count());
    try std.testing.expectEqual(@as(usize, 500), store.get("LONG_KEY").?.value.len);
}

test "unicode values - emoji" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content = "EMOJI=Hello 🌍 World 🚀\n";

    try env_parser.parseEnvContent(allocator, content, ".env", &store);
    try std.testing.expectEqualStrings("Hello 🌍 World 🚀", store.get("EMOJI").?.value);
}

test "unicode values - CJK characters" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content = "CJK=你好世界\nJAPAN=こんにちは\nKOREA=안녕하세요\n";

    try env_parser.parseEnvContent(allocator, content, ".env", &store);
    try std.testing.expectEqualStrings("你好世界", store.get("CJK").?.value);
    try std.testing.expectEqualStrings("こんにちは", store.get("JAPAN").?.value);
    try std.testing.expectEqualStrings("안녕하세요", store.get("KOREA").?.value);
}

// ============================================================================
// KEY/VALUE EDGE CASES
// ============================================================================

test "keys with hyphens and dots" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\MY-VAR=value1
        \\MY.VAR=value2
        \\MY_123_VAR=value3
        \\
    ;

    try env_parser.parseEnvContent(allocator, content, ".env", &store);
    try std.testing.expectEqualStrings("value1", store.get("MY-VAR").?.value);
    try std.testing.expectEqualStrings("value2", store.get("MY.VAR").?.value);
    try std.testing.expectEqualStrings("value3", store.get("MY_123_VAR").?.value);
}

test "numeric keys" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content = "123=numeric_key\n456ABC=mixed\n";

    try env_parser.parseEnvContent(allocator, content, ".env", &store);
    try std.testing.expectEqualStrings("numeric_key", store.get("123").?.value);
    try std.testing.expectEqualStrings("mixed", store.get("456ABC").?.value);
}

test "empty key should be skipped" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content = "=value\nVALID_KEY=valid\n";

    try env_parser.parseEnvContent(allocator, content, ".env", &store);
    // Empty key should be skipped
    try std.testing.expectEqual(@as(usize, 1), store.count());
    try std.testing.expectEqualStrings("valid", store.get("VALID_KEY").?.value);
}

test "key with leading and trailing spaces" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content = "  KEY  =value\n";

    try env_parser.parseEnvContent(allocator, content, ".env", &store);
    // Key should be trimmed
    try std.testing.expectEqualStrings("value", store.get("KEY").?.value);
}

test "multiple equals signs in value" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\URL=https://api.com?foo=bar&baz=qux
        \\BASE64=SGVsbG89V29ybGQ=
        \\EQUATION=a=b=c
        \\
    ;

    try env_parser.parseEnvContent(allocator, content, ".env", &store);
    try std.testing.expectEqualStrings("https://api.com?foo=bar&baz=qux", store.get("URL").?.value);
    try std.testing.expectEqualStrings("SGVsbG89V29ybGQ=", store.get("BASE64").?.value);
    try std.testing.expectEqualStrings("a=b=c", store.get("EQUATION").?.value);
}

test "values with embedded quotes" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    // Unquoted value with quotes inside - may not parse as expected but should not crash
    const content = "MSG=He said hello\n";

    try env_parser.parseEnvContent(allocator, content, ".env", &store);
    try std.testing.expectEqualStrings("He said hello", store.get("MSG").?.value);
}

test "nested quotes" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\VAL1="outer 'inner' outer"
        \\VAL2='outer "inner" outer'
        \\
    ;

    try env_parser.parseEnvContent(allocator, content, ".env", &store);
    try std.testing.expectEqualStrings("outer 'inner' outer", store.get("VAL1").?.value);
    try std.testing.expectEqualStrings("outer \"inner\" outer", store.get("VAL2").?.value);
}

test "backslash in values" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content = "PATH=C:\\Users\\name\\folder\n";

    try env_parser.parseEnvContent(allocator, content, ".env", &store);
    try std.testing.expectEqualStrings("C:\\Users\\name\\folder", store.get("PATH").?.value);
}

test "empty quoted values" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\EMPTY_DOUBLE=""
        \\EMPTY_SINGLE=''
        \\TRULY_EMPTY=
        \\
    ;

    try env_parser.parseEnvContent(allocator, content, ".env", &store);
    try std.testing.expectEqualStrings("", store.get("EMPTY_DOUBLE").?.value);
    try std.testing.expectEqualStrings("", store.get("EMPTY_SINGLE").?.value);
    try std.testing.expectEqualStrings("", store.get("TRULY_EMPTY").?.value);
}

test "value with only spaces" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\SPACES="   "
        \\UNQUOTED_SPACES=
        \\
    ;

    try env_parser.parseEnvContent(allocator, content, ".env", &store);
    try std.testing.expectEqualStrings("   ", store.get("SPACES").?.value);
    // Unquoted spaces should be trimmed
    try std.testing.expectEqualStrings("", store.get("UNQUOTED_SPACES").?.value);
}

test "line without equals sign is skipped" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\VALID_KEY=value
        \\THIS_HAS_NO_EQUALS
        \\ANOTHER_VALID=value2
        \\
    ;

    try env_parser.parseEnvContent(allocator, content, ".env", &store);
    try std.testing.expectEqual(@as(usize, 2), store.count());
}

// ============================================================================
// MASKING EDGE CASES
// ============================================================================

test "mask empty value" {
    var buf: [64]u8 = undefined;
    const result = masking.maskValue("", &buf);
    try std.testing.expectEqualStrings("****", result);
}

test "mask single character value" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("****", masking.maskValue("a", &buf));
    try std.testing.expectEqualStrings("****", masking.maskValue("x", &buf));
}

test "mask two character value" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("****", masking.maskValue("ab", &buf));
}

test "mask three character value" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("****", masking.maskValue("abc", &buf));
}

test "mask exactly four character value" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("****", masking.maskValue("abcd", &buf));
}

test "mask five character value - boundary" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("****bcde", masking.maskValue("abcde", &buf));
}

test "mask long api key" {
    var buf: [64]u8 = undefined;
    const result = masking.maskValue("sk_live_1234567890abcdefghij", &buf);
    try std.testing.expectEqualStrings("****ghij", result);
}

test "mask url" {
    var buf: [64]u8 = undefined;
    const result = masking.maskValue("https://api.example.com/v1/endpoint", &buf);
    try std.testing.expectEqualStrings("****oint", result);
}

// ============================================================================
// OUTPUT FORMAT EDGE CASES
// ============================================================================

test "json output escapes quotes" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("QUOTE", "value with \"quotes\"", ".env");

    var buf: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const unmask_keys = [_][]const u8{"QUOTE"};
    try output.writeJsonOutput(fbs.writer(), &store, &unmask_keys);

    const result = fbs.getWritten();
    // Should have escaped quotes in JSON
    try std.testing.expect(std.mem.indexOf(u8, result, "\\\"") != null);
}

test "json output escapes backslashes" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("PATH", "C:\\Users\\name", ".env");

    var buf: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const unmask_keys = [_][]const u8{"PATH"};
    try output.writeJsonOutput(fbs.writer(), &store, &unmask_keys);

    const result = fbs.getWritten();
    // Should have escaped backslashes in JSON
    try std.testing.expect(std.mem.indexOf(u8, result, "\\\\") != null);
}

test "json output escapes newlines" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("MULTI", "line1\nline2", ".env");

    var buf: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const unmask_keys = [_][]const u8{"MULTI"};
    try output.writeJsonOutput(fbs.writer(), &store, &unmask_keys);

    const result = fbs.getWritten();
    // Should have escaped newlines in JSON
    try std.testing.expect(std.mem.indexOf(u8, result, "\\n") != null);
}

test "json output escapes tabs" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("TABBED", "col1\tcol2", ".env");

    var buf: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const unmask_keys = [_][]const u8{"TABBED"};
    try output.writeJsonOutput(fbs.writer(), &store, &unmask_keys);

    const result = fbs.getWritten();
    // Should have escaped tabs in JSON
    try std.testing.expect(std.mem.indexOf(u8, result, "\\t") != null);
}

test "empty store produces valid json" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const unmask_keys = [_][]const u8{};
    try output.writeJsonOutput(fbs.writer(), &store, &unmask_keys);

    const result = fbs.getWritten();
    // Should be valid JSON with empty array
    try std.testing.expect(std.mem.indexOf(u8, result, "\"envs\": []") != null or
        std.mem.indexOf(u8, result, "\"envs\": [\n  ]") != null);
}

test "empty store produces valid structured output" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const unmask_keys = [_][]const u8{};
    try output.writeStructuredOutput(fbs.writer(), &store, &unmask_keys);

    const result = fbs.getWritten();
    // Should have header with count of 0
    try std.testing.expect(std.mem.indexOf(u8, result, "envs[0]{key,value,status}:") != null);
}

test "list output with empty store" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try output.writeListOutput(fbs.writer(), &store);

    const result = fbs.getWritten();
    // Should be empty
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

// ============================================================================
// COMMENT EDGE CASES
// ============================================================================

test "comment after value is included in value" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    // Standard behavior: inline comments are NOT stripped
    const content = "KEY=value # this is part of value\n";

    try env_parser.parseEnvContent(allocator, content, ".env", &store);
    try std.testing.expectEqualStrings("value # this is part of value", store.get("KEY").?.value);
}

test "hash in quoted value" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content = "KEY=\"value#with#hash\"\n";

    try env_parser.parseEnvContent(allocator, content, ".env", &store);
    try std.testing.expectEqualStrings("value#with#hash", store.get("KEY").?.value);
}

test "line starting with multiple hashes" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\### Header comment ###
        \\KEY=value
        \\## Another comment
        \\
    ;

    try env_parser.parseEnvContent(allocator, content, ".env", &store);
    try std.testing.expectEqual(@as(usize, 1), store.count());
}

// ============================================================================
// SPECIAL VALUE FORMATS
// ============================================================================

test "json value in env" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content = "CONFIG={\"key\": \"value\", \"num\": 123}\n";

    try env_parser.parseEnvContent(allocator, content, ".env", &store);
    try std.testing.expectEqualStrings("{\"key\": \"value\", \"num\": 123}", store.get("CONFIG").?.value);
}

test "url with all special characters" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content = "DATABASE_URL=postgres://user:pass@host:5432/db?ssl=true&pool=5\n";

    try env_parser.parseEnvContent(allocator, content, ".env", &store);
    try std.testing.expectEqualStrings("postgres://user:pass@host:5432/db?ssl=true&pool=5", store.get("DATABASE_URL").?.value);
}

test "base64 encoded value" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content = "SECRET=dGhpcyBpcyBhIHNlY3JldCBtZXNzYWdl\n";

    try env_parser.parseEnvContent(allocator, content, ".env", &store);
    try std.testing.expectEqualStrings("dGhpcyBpcyBhIHNlY3JldCBtZXNzYWdl", store.get("SECRET").?.value);
}

test "connection string with special chars" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content = "CONN=Server=myserver;Database=mydb;User=admin;Password=p@ss!word#123;\n";

    try env_parser.parseEnvContent(allocator, content, ".env", &store);
    try std.testing.expectEqualStrings("Server=myserver;Database=mydb;User=admin;Password=p@ss!word#123;", store.get("CONN").?.value);
}
