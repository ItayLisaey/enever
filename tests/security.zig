const std = @import("std");
const env_parser = @import("env-parser");
const masking = @import("masking");
const output = @import("output");

// ============================================================================
// MASKING CONSISTENCY TESTS
// Tests to ensure ALL output paths properly mask values
// ============================================================================

test "masking - all values masked by default in structured output" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    // Add various types of sensitive data
    try store.put("API_KEY", "sk_live_1234567890abcdef", ".env");
    try store.put("DATABASE_PASSWORD", "super_secret_password", ".env");
    try store.put("JWT_SECRET", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9", ".env");
    try store.put("AWS_SECRET_KEY", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY", ".env");

    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const no_unmask = [_][]const u8{};
    try output.writeStructuredOutput(fbs.writer(), &store, &no_unmask);

    const result = fbs.getWritten();

    // Verify NONE of the actual values appear in output
    try std.testing.expect(std.mem.indexOf(u8, result, "sk_live_1234567890abcdef") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "super_secret_password") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY") == null);

    // All should show as masked
    try std.testing.expect(std.mem.indexOf(u8, result, ",masked") != null);
}

test "masking - all values masked by default in json output" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("SECRET", "this_is_very_secret_do_not_expose", ".env");
    try store.put("TOKEN", "ghp_1234567890abcdefghijklmnop", ".env");

    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const no_unmask = [_][]const u8{};
    try output.writeJsonOutput(fbs.writer(), &store, &no_unmask);

    const result = fbs.getWritten();

    // Verify actual values don't appear
    try std.testing.expect(std.mem.indexOf(u8, result, "this_is_very_secret_do_not_expose") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "ghp_1234567890abcdefghijklmnop") == null);

    // All should show as masked status
    try std.testing.expect(std.mem.indexOf(u8, result, "\"status\": \"masked\"") != null);
}

test "masking - single value masked by default" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("PRIVATE_KEY", "-----BEGIN RSA PRIVATE KEY-----", ".env");

    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try output.writeSingleValue(fbs.writer(), store.get("PRIVATE_KEY").?, false, false);

    const result = fbs.getWritten();

    // Should NOT contain the private key
    try std.testing.expect(std.mem.indexOf(u8, result, "-----BEGIN RSA PRIVATE KEY-----") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "****") != null);
}

test "masking - list output never shows values" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("SECRET1", "absolutely_secret_value_1", ".env");
    try store.put("SECRET2", "absolutely_secret_value_2", ".env");

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try output.writeListOutput(fbs.writer(), &store);

    const result = fbs.getWritten();

    // Should only show keys
    try std.testing.expect(std.mem.indexOf(u8, result, "SECRET1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "SECRET2") != null);

    // Should NOT contain any values
    try std.testing.expect(std.mem.indexOf(u8, result, "absolutely_secret_value") == null);
}

// ============================================================================
// UNMASK FUNCTIONALITY TESTS
// Tests to ensure unmask only exposes specifically requested keys
// ============================================================================

test "unmask - only specified key is revealed" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("PUBLIC_API", "api_key_12345678", ".env");
    try store.put("PRIVATE_SECRET", "secret_that_must_stay_hidden", ".env");
    try store.put("ANOTHER_SECRET", "another_hidden_value", ".env");

    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    // Only unmask PUBLIC_API
    const unmask_keys = [_][]const u8{"PUBLIC_API"};
    try output.writeStructuredOutput(fbs.writer(), &store, &unmask_keys);

    const result = fbs.getWritten();

    // PUBLIC_API should be visible
    try std.testing.expect(std.mem.indexOf(u8, result, "api_key_12345678") != null);

    // Others should NOT be visible
    try std.testing.expect(std.mem.indexOf(u8, result, "secret_that_must_stay_hidden") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "another_hidden_value") == null);
}

test "unmask - non-existent key in unmask list is handled safely" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("REAL_KEY", "real_value", ".env");

    var buf: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    // Try to unmask a key that doesn't exist
    const unmask_keys = [_][]const u8{"NON_EXISTENT_KEY"};
    try output.writeStructuredOutput(fbs.writer(), &store, &unmask_keys);

    // Should not crash, REAL_KEY should still be masked
    const result = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, result, "real_value") == null);
}

// ============================================================================
// MEMORY SECURITY TESTS
// Tests related to memory handling of sensitive values
// ============================================================================

test "memory - store properly frees entries on deinit" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);

    try store.put("KEY1", "value1", ".env");
    try store.put("KEY2", "value2", ".env");
    try store.put("KEY3", "value3", ".env");

    // deinit should free all memory without leaks
    // The testing allocator will catch any leaks
    store.deinit();
}

test "memory - store handles replacement without leaks" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    // Add and replace multiple times
    try store.put("KEY", "value1", ".env");
    try store.put("KEY", "value2", ".env");
    try store.put("KEY", "value3", ".env");
    try store.put("KEY", "final_value", ".env");

    try std.testing.expectEqual(@as(usize, 1), store.count());
    try std.testing.expectEqualStrings("final_value", store.get("KEY").?.value);
}

test "memory - parse content doesn't leak on large input" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    // Create content with many variables
    var content: [8192]u8 = undefined;
    var pos: usize = 0;

    var i: usize = 0;
    while (i < 50) : (i += 1) {
        const written = std.fmt.bufPrint(content[pos..], "KEY_{d}=value_{d}\n", .{ i, i }) catch break;
        pos += written.len;
    }

    try env_parser.parseEnvContent(allocator, content[0..pos], ".env", &store);

    // Should have parsed all entries
    try std.testing.expectEqual(@as(usize, 50), store.count());
}

// ============================================================================
// VALUE MASKING SECURITY TESTS
// Tests that masking properly hides sensitive information
// ============================================================================

test "mask - short values fully hidden" {
    var buf: [64]u8 = undefined;

    // Values <= 4 chars should be completely hidden
    try std.testing.expectEqualStrings("****", masking.maskValue("", &buf));
    try std.testing.expectEqualStrings("****", masking.maskValue("a", &buf));
    try std.testing.expectEqualStrings("****", masking.maskValue("ab", &buf));
    try std.testing.expectEqualStrings("****", masking.maskValue("abc", &buf));
    try std.testing.expectEqualStrings("****", masking.maskValue("abcd", &buf));
}

test "mask - only last 4 chars visible for longer values" {
    var buf: [64]u8 = undefined;

    // For values > 4 chars, only last 4 should be visible
    const result = masking.maskValue("secret_password_12345", &buf);
    try std.testing.expectEqualStrings("****2345", result);

    // Verify the secret part is NOT in the result
    try std.testing.expect(std.mem.indexOf(u8, result, "secret") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "password") == null);
}

test "mask - common secret patterns are hidden" {
    var buf: [64]u8 = undefined;

    // API keys
    const api_key = masking.maskValue("sk_live_abcdef1234567890", &buf);
    try std.testing.expect(std.mem.indexOf(u8, api_key, "sk_live") == null);

    // GitHub tokens
    const gh_token = masking.maskValue("ghp_abcdefghijklmnopqrstuvwxyz", &buf);
    try std.testing.expect(std.mem.indexOf(u8, gh_token, "ghp_") == null);

    // AWS keys
    const aws_key = masking.maskValue("AKIAIOSFODNN7EXAMPLE", &buf);
    try std.testing.expect(std.mem.indexOf(u8, aws_key, "AKIA") == null);
}

// ============================================================================
// INPUT VALIDATION SECURITY TESTS
// Tests for handling potentially malicious input
// ============================================================================

test "security - handles null bytes in content" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    // Content with null byte - should handle gracefully
    const content = "KEY=before\x00after\n";
    try env_parser.parseEnvContent(allocator, content, ".env", &store);

    // Should parse what it can
    const entry = store.get("KEY");
    try std.testing.expect(entry != null);
}

test "security - handles very long lines" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    // Create a very long line (but within limits)
    var long_line: [2048]u8 = undefined;
    @memset(&long_line, 'a');
    long_line[0] = 'K';
    long_line[1] = 'E';
    long_line[2] = 'Y';
    long_line[3] = '=';
    long_line[2047] = '\n';

    try env_parser.parseEnvContent(allocator, &long_line, ".env", &store);

    // Should have parsed the key
    try std.testing.expect(store.get("KEY") != null);
}

test "security - malformed lines don't crash" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const malformed_content =
        \\=no_key
        \\
        \\==double_equals
        \\no_equals_at_all
        \\
        \\KEY=valid
        \\###
        \\= = =
        \\
    ;

    // Should not crash on malformed input
    try env_parser.parseEnvContent(allocator, malformed_content, ".env", &store);

    // Valid line should still be parsed
    try std.testing.expect(store.get("KEY") != null);
}

// ============================================================================
// OUTPUT ESCAPING SECURITY TESTS
// Tests that output is properly escaped to prevent injection
// ============================================================================

test "security - json output escapes special characters" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    // Add value with characters that need JSON escaping
    try store.put("INJECT", "value\nwith\"special\\chars\t", ".env");

    var buf: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const unmask_keys = [_][]const u8{"INJECT"};
    try output.writeJsonOutput(fbs.writer(), &store, &unmask_keys);

    const result = fbs.getWritten();

    // Should have escaped characters
    try std.testing.expect(std.mem.indexOf(u8, result, "\\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\\\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\\\\") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\\t") != null);
}

test "security - structured output handles special chars safely" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    // Add value with commas (CSV-like format)
    try store.put("CSV_LIKE", "value,with,commas", ".env");

    var buf: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const unmask_keys = [_][]const u8{"CSV_LIKE"};
    try output.writeStructuredOutput(fbs.writer(), &store, &unmask_keys);

    // Should not crash - output format handles it
    const result = fbs.getWritten();
    try std.testing.expect(result.len > 0);
}

// ============================================================================
// MASKING STATUS TESTS
// Tests that mask status is correctly assigned
// ============================================================================

test "masking status - all new entries are masked by default" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("PUBLIC_URL", "https://example.com", ".env");
    try store.put("SECRET_KEY", "secret123", ".env");
    try store.put("PORT", "3000", ".env");

    // All should be masked by default
    try std.testing.expectEqual(masking.MaskStatus.masked, store.get("PUBLIC_URL").?.mask_status);
    try std.testing.expectEqual(masking.MaskStatus.masked, store.get("SECRET_KEY").?.mask_status);
    try std.testing.expectEqual(masking.MaskStatus.masked, store.get("PORT").?.mask_status);
}

test "masking status - getMaskStatus always returns masked" {
    // Security first: all values are masked regardless of key name
    try std.testing.expectEqual(masking.MaskStatus.masked, masking.getMaskStatus("PUBLIC_URL"));
    try std.testing.expectEqual(masking.MaskStatus.masked, masking.getMaskStatus("SECRET_KEY"));
    try std.testing.expectEqual(masking.MaskStatus.masked, masking.getMaskStatus("NODE_ENV"));
    try std.testing.expectEqual(masking.MaskStatus.masked, masking.getMaskStatus("PORT"));
    try std.testing.expectEqual(masking.MaskStatus.masked, masking.getMaskStatus("DEBUG"));
}

// ============================================================================
// FILE PARSING SECURITY TESTS
// ============================================================================

test "security - parse handles empty content" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try env_parser.parseEnvContent(allocator, "", ".env", &store);
    try std.testing.expectEqual(@as(usize, 0), store.count());
}

test "security - parse handles content with only whitespace" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try env_parser.parseEnvContent(allocator, "   \n\t\n   \n", ".env", &store);
    try std.testing.expectEqual(@as(usize, 0), store.count());
}

test "security - parse handles content with only comments" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\# Comment 1
        \\# Comment 2
        \\### Header ###
        \\# Comment 3
        \\
    ;

    try env_parser.parseEnvContent(allocator, content, ".env", &store);
    try std.testing.expectEqual(@as(usize, 0), store.count());
}
