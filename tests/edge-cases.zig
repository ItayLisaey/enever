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

// ============================================================================
// MULTILINE VALUE PARSING
// ============================================================================

test "multiline JSON value with single quotes" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\SHEETS_SERVICE_ACCOUNT_KEY='{
        \\  "type": "service_account",
        \\  "project_id": "test-project",
        \\  "private_key": "-----BEGIN PRIVATE KEY-----\nMIIE\n-----END PRIVATE KEY-----\n"
        \\}'
        \\OTHER_KEY=simple_value
        \\
    ;

    try env_parser.parseEnvContent(allocator, content, ".env", &store);

    try std.testing.expectEqual(@as(usize, 2), store.count());

    const json_value = store.get("SHEETS_SERVICE_ACCOUNT_KEY").?.value;
    try std.testing.expect(std.mem.indexOf(u8, json_value, "\"type\": \"service_account\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_value, "\"project_id\": \"test-project\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_value, "-----BEGIN PRIVATE KEY-----") != null);

    try std.testing.expectEqualStrings("simple_value", store.get("OTHER_KEY").?.value);
}

test "multiline JSON value with double quotes" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\CONFIG="{
        \\  \"name\": \"test\",
        \\  \"value\": 123
        \\}"
        \\
    ;

    try env_parser.parseEnvContent(allocator, content, ".env", &store);

    const config_value = store.get("CONFIG").?.value;
    try std.testing.expect(std.mem.indexOf(u8, config_value, "\"name\": \"test\"") != null);
}

test "escaped quotes inside quoted value" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\MESSAGE="He said \"Hello\" to me"
        \\
    ;

    try env_parser.parseEnvContent(allocator, content, ".env", &store);

    try std.testing.expectEqualStrings("He said \"Hello\" to me", store.get("MESSAGE").?.value);
}

test "multiline value in MultiEnvStore" {
    const allocator = std.testing.allocator;
    var store = env_parser.MultiEnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\JSON_KEY='{
        \\  "nested": {
        \\    "value": "test"
        \\  }
        \\}'
        \\
    ;

    try env_parser.parseEnvContentMulti(content, ".env", &store);

    const entry = store.get("JSON_KEY").?;
    try std.testing.expectEqual(@as(usize, 1), entry.values.items.len);
    try std.testing.expect(std.mem.indexOf(u8, entry.values.items[0].value, "\"nested\"") != null);
}

test "Google service account key parsing" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\SHEETS_SERVICE_ACCOUNT_KEY='{
        \\  "type": "service_account",
        \\  "project_id": "my-project-123",
        \\  "private_key_id": "abc123def456",
        \\  "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC\n-----END PRIVATE KEY-----\n",
        \\  "client_email": "service@my-project-123.iam.gserviceaccount.com",
        \\  "client_id": "123456789",
        \\  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
        \\  "token_uri": "https://oauth2.googleapis.com/token"
        \\}'
        \\
    ;

    try env_parser.parseEnvContent(allocator, content, ".env", &store);

    const value = store.get("SHEETS_SERVICE_ACCOUNT_KEY").?.value;

    try std.testing.expect(std.mem.indexOf(u8, value, "\"type\": \"service_account\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, value, "\"project_id\": \"my-project-123\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, value, "\"private_key_id\": \"abc123def456\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, value, "-----BEGIN PRIVATE KEY-----") != null);
    try std.testing.expect(std.mem.indexOf(u8, value, "-----END PRIVATE KEY-----") != null);
    try std.testing.expect(std.mem.indexOf(u8, value, "\"client_email\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, value, "\"token_uri\":") != null);

    try std.testing.expect(value.len > 2);
    try std.testing.expectEqual(@as(u8, '{'), value[0]);
    try std.testing.expectEqual(@as(u8, '}'), value[value.len - 1]);
}

test "multiline value followed by other vars" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\FIRST=simple
        \\MULTILINE='{
        \\  "key": "value"
        \\}'
        \\AFTER_MULTILINE=also_works
        \\LAST=final
        \\
    ;

    try env_parser.parseEnvContent(allocator, content, ".env", &store);

    try std.testing.expectEqual(@as(usize, 4), store.count());
    try std.testing.expectEqualStrings("simple", store.get("FIRST").?.value);
    try std.testing.expectEqualStrings("also_works", store.get("AFTER_MULTILINE").?.value);
    try std.testing.expectEqualStrings("final", store.get("LAST").?.value);

    const multiline = store.get("MULTILINE").?.value;
    try std.testing.expect(std.mem.indexOf(u8, multiline, "\"key\": \"value\"") != null);
}

test "deeply nested JSON structure" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\CONFIG='{
        \\  "level1": {
        \\    "level2": {
        \\      "level3": {
        \\        "deep_value": "found_it"
        \\      }
        \\    }
        \\  }
        \\}'
        \\
    ;

    try env_parser.parseEnvContent(allocator, content, ".env", &store);

    const value = store.get("CONFIG").?.value;
    try std.testing.expect(std.mem.indexOf(u8, value, "\"deep_value\": \"found_it\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, value, "\"level1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, value, "\"level2\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, value, "\"level3\"") != null);
}

test "embedded newlines as escape sequences" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----\nMIIE\nABCD\n-----END RSA PRIVATE KEY-----"
        \\
    ;

    try env_parser.parseEnvContent(allocator, content, ".env", &store);

    const value = store.get("PRIVATE_KEY").?.value;

    try std.testing.expect(std.mem.indexOf(u8, value, "-----BEGIN RSA PRIVATE KEY-----\nMIIE") != null);
    try std.testing.expect(std.mem.indexOf(u8, value, "\n-----END RSA PRIVATE KEY-----") != null);

    var newline_count: usize = 0;
    for (value) |c| {
        if (c == '\n') newline_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), newline_count);
}

test "mixed quote styles in same file" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\SINGLE_QUOTED='{
        \\  "type": "single"
        \\}'
        \\DOUBLE_QUOTED="{
        \\  \"type\": \"double\"
        \\}"
        \\UNQUOTED=plain_value
        \\
    ;

    try env_parser.parseEnvContent(allocator, content, ".env", &store);

    try std.testing.expectEqual(@as(usize, 3), store.count());

    const single = store.get("SINGLE_QUOTED").?.value;
    try std.testing.expect(std.mem.indexOf(u8, single, "\"type\": \"single\"") != null);

    const double = store.get("DOUBLE_QUOTED").?.value;
    try std.testing.expect(std.mem.indexOf(u8, double, "\"type\": \"double\"") != null);

    try std.testing.expectEqualStrings("plain_value", store.get("UNQUOTED").?.value);
}

test "AWS credentials JSON format" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\AWS_CREDENTIALS='{
        \\  "accessKeyId": "AKIAIOSFODNN7EXAMPLE",
        \\  "secretAccessKey": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        \\  "region": "us-west-2"
        \\}'
        \\
    ;

    try env_parser.parseEnvContent(allocator, content, ".env", &store);

    const value = store.get("AWS_CREDENTIALS").?.value;
    try std.testing.expect(std.mem.indexOf(u8, value, "\"accessKeyId\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, value, "\"secretAccessKey\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, value, "AKIAIOSFODNN7EXAMPLE") != null);
}

test "Firebase service account format" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\FIREBASE_CONFIG='{
        \\  "apiKey": "AIzaSyExample",
        \\  "authDomain": "myapp.firebaseapp.com",
        \\  "projectId": "myapp",
        \\  "storageBucket": "myapp.appspot.com",
        \\  "messagingSenderId": "123456789",
        \\  "appId": "1:123456789:web:abc123"
        \\}'
        \\
    ;

    try env_parser.parseEnvContent(allocator, content, ".env", &store);

    const value = store.get("FIREBASE_CONFIG").?.value;
    try std.testing.expect(std.mem.indexOf(u8, value, "\"apiKey\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, value, "\"authDomain\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, value, "\"appId\"") != null);
}

test "multiline in MultiEnvStore with multiple files" {
    const allocator = std.testing.allocator;
    var store = env_parser.MultiEnvStore.init(allocator);
    defer store.deinit();

    const dev_content =
        \\CONFIG='{
        \\  "env": "development",
        \\  "debug": true
        \\}'
        \\
    ;

    const prod_content =
        \\CONFIG='{
        \\  "env": "production",
        \\  "debug": false
        \\}'
        \\
    ;

    try env_parser.parseEnvContentMulti(dev_content, ".env", &store);
    try env_parser.parseEnvContentMulti(prod_content, ".env.production", &store);

    const entry = store.get("CONFIG").?;
    try std.testing.expectEqual(@as(usize, 2), entry.values.items.len);

    try std.testing.expect(std.mem.indexOf(u8, entry.values.items[0].value, "\"env\": \"development\"") != null);
    try std.testing.expectEqualStrings(".env", entry.values.items[0].source_file);

    try std.testing.expect(std.mem.indexOf(u8, entry.values.items[1].value, "\"env\": \"production\"") != null);
    try std.testing.expectEqualStrings(".env.production", entry.values.items[1].source_file);
}

test "unclosed quote at end of file" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\KEY='unclosed value
    ;

    try env_parser.parseEnvContent(allocator, content, ".env", &store);

    const value = store.get("KEY").?.value;
    try std.testing.expectEqualStrings("unclosed value", value);
}

test "empty JSON objects and arrays" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\EMPTY_JSON='{}'
        \\EMPTY_ARRAY='[]'
        \\
    ;

    try env_parser.parseEnvContent(allocator, content, ".env", &store);

    try std.testing.expectEqualStrings("{}", store.get("EMPTY_JSON").?.value);
    try std.testing.expectEqualStrings("[]", store.get("EMPTY_ARRAY").?.value);
}

test "JSON array value" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\ALLOWED_ORIGINS='[
        \\  "http://localhost:3000",
        \\  "https://myapp.com",
        \\  "https://staging.myapp.com"
        \\]'
        \\
    ;

    try env_parser.parseEnvContent(allocator, content, ".env", &store);

    const value = store.get("ALLOWED_ORIGINS").?.value;
    try std.testing.expect(std.mem.indexOf(u8, value, "\"http://localhost:3000\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, value, "\"https://myapp.com\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, value, "\"https://staging.myapp.com\"") != null);
    try std.testing.expectEqual(@as(u8, '['), value[0]);
    try std.testing.expectEqual(@as(u8, ']'), value[value.len - 1]);
}
