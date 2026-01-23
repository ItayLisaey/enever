const std = @import("std");
const env_parser = @import("env-parser");
const masking = @import("masking");
const output = @import("output");

// Integration tests for enever

test "full environment resolution priority" {
    const allocator = std.testing.allocator;

    // Create test directory
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create .env file
    const env_file = try tmp_dir.dir.createFile(".env", .{});
    try env_file.writeAll("BASE_KEY=base_value\nOVERRIDE_KEY=from_base\n");
    env_file.close();

    // Create .env.development file
    const dev_file = try tmp_dir.dir.createFile(".env.development", .{});
    try dev_file.writeAll("DEV_KEY=dev_value\nOVERRIDE_KEY=from_dev\n");
    dev_file.close();

    // Create .env.local file
    const local_file = try tmp_dir.dir.createFile(".env.local", .{});
    try local_file.writeAll("LOCAL_KEY=local_value\nOVERRIDE_KEY=from_local\n");
    local_file.close();

    // Parse files manually to test priority
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    // Load in priority order (lowest to highest)
    {
        const path = try tmp_dir.dir.realpathAlloc(allocator, ".env");
        defer allocator.free(path);
        try env_parser.parseEnvFile(allocator, path, &store);
    }
    {
        const path = try tmp_dir.dir.realpathAlloc(allocator, ".env.development");
        defer allocator.free(path);
        try env_parser.parseEnvFile(allocator, path, &store);
    }
    {
        const path = try tmp_dir.dir.realpathAlloc(allocator, ".env.local");
        defer allocator.free(path);
        try env_parser.parseEnvFile(allocator, path, &store);
    }

    // Verify all keys exist
    try std.testing.expectEqualStrings("base_value", store.get("BASE_KEY").?.value);
    try std.testing.expectEqualStrings("dev_value", store.get("DEV_KEY").?.value);
    try std.testing.expectEqualStrings("local_value", store.get("LOCAL_KEY").?.value);

    // Verify override priority (local wins)
    try std.testing.expectEqualStrings("from_local", store.get("OVERRIDE_KEY").?.value);
}

test "all values masked by default" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\API_URL=https://api.example.com
        \\PORT=3000
        \\NODE_ENV=development
        \\API_KEY=sk_live_abcdef123456
        \\
    ;

    try env_parser.parseEnvContent(allocator, content, ".env", &store);

    // All keys should be masked
    try std.testing.expectEqual(masking.MaskStatus.masked, store.get("API_URL").?.mask_status);
    try std.testing.expectEqual(masking.MaskStatus.masked, store.get("PORT").?.mask_status);
    try std.testing.expectEqual(masking.MaskStatus.masked, store.get("NODE_ENV").?.mask_status);
    try std.testing.expectEqual(masking.MaskStatus.masked, store.get("API_KEY").?.mask_status);
}

test "output format structured vs json" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("API_URL", "https://api.v1.com", ".env");
    try store.put("DB_PORT", "5432", ".env");

    // Test structured output - all values masked
    {
        var buf: [2048]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        const unmask_keys = [_][]const u8{};
        try output.writeStructuredOutput(fbs.writer(), &store, &unmask_keys);
        const structured = fbs.getWritten();

        // Verify header format
        try std.testing.expect(std.mem.indexOf(u8, structured, "envs[2]{key,value,status}:") != null);

        // All values should be masked
        try std.testing.expect(std.mem.indexOf(u8, structured, "API_URL,****.com,masked") != null);
        try std.testing.expect(std.mem.indexOf(u8, structured, "DB_PORT,****,masked") != null);
    }

    // Test JSON output
    {
        var buf: [2048]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        const unmask_keys = [_][]const u8{};
        try output.writeJsonOutput(fbs.writer(), &store, &unmask_keys);
        const json_out = fbs.getWritten();

        // Verify JSON structure
        try std.testing.expect(std.mem.indexOf(u8, json_out, "\"envs\":") != null);
        try std.testing.expect(std.mem.indexOf(u8, json_out, "\"key\": \"API_URL\"") != null);
        try std.testing.expect(std.mem.indexOf(u8, json_out, "\"status\": \"masked\"") != null);
    }
}

test "unmask specific key" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("API_KEY", "sk_live_secret123456", ".env");
    try store.put("API_SECRET", "very_secret_value", ".env");

    // Test with unmask
    {
        var buf: [2048]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        const unmask_keys = [_][]const u8{"API_KEY"};
        try output.writeStructuredOutput(fbs.writer(), &store, &unmask_keys);
        const result = fbs.getWritten();

        // API_KEY should be unmasked
        try std.testing.expect(std.mem.indexOf(u8, result, "API_KEY,sk_live_secret123456,public") != null);

        // API_SECRET should still be masked
        try std.testing.expect(std.mem.indexOf(u8, result, "API_SECRET,****alue,masked") != null);
    }
}

test "empty env file handling" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try env_parser.parseEnvContent(allocator, "", ".env", &store);
    try std.testing.expectEqual(@as(usize, 0), store.count());
}

test "comments and whitespace handling" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\# This is a header comment
        \\
        \\   # Indented comment
        \\KEY1=value1
        \\
        \\  KEY2  =  value2
        \\
        \\# Another comment
        \\KEY3="quoted value with spaces"
        \\KEY4='single quoted'
        \\
        \\# Trailing comment
        \\
    ;

    try env_parser.parseEnvContent(allocator, content, ".env", &store);

    try std.testing.expectEqual(@as(usize, 4), store.count());
    try std.testing.expectEqualStrings("value1", store.get("KEY1").?.value);
    try std.testing.expectEqualStrings("value2", store.get("KEY2").?.value);
    try std.testing.expectEqualStrings("quoted value with spaces", store.get("KEY3").?.value);
    try std.testing.expectEqualStrings("single quoted", store.get("KEY4").?.value);
}

test "special characters in values" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\URL=https://example.com/path?query=value&other=123
        \\JSON_VALUE={"key":"value"}
        \\EQUALS=a=b=c
        \\
    ;

    try env_parser.parseEnvContent(allocator, content, ".env", &store);

    try std.testing.expectEqualStrings("https://example.com/path?query=value&other=123", store.get("URL").?.value);
    try std.testing.expectEqualStrings("{\"key\":\"value\"}", store.get("JSON_VALUE").?.value);
    try std.testing.expectEqualStrings("a=b=c", store.get("EQUALS").?.value);
}

test "mask value edge cases" {
    var buf: [64]u8 = undefined;

    // Empty value
    try std.testing.expectEqualStrings("****", masking.maskValue("", &buf));

    // 1 char
    try std.testing.expectEqualStrings("****", masking.maskValue("a", &buf));

    // 4 chars (boundary)
    try std.testing.expectEqualStrings("****", masking.maskValue("abcd", &buf));

    // 5 chars (just over boundary)
    try std.testing.expectEqualStrings("****bcde", masking.maskValue("abcde", &buf));

    // Long value
    const long_result = masking.maskValue("sk_live_1234567890abcdef", &buf);
    try std.testing.expectEqualStrings("****cdef", long_result);
}

test "list output sorted alphabetically" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("ZEBRA", "z", ".env");
    try store.put("APPLE", "a", ".env");
    try store.put("MANGO", "m", ".env");
    try store.put("BANANA", "b", ".env");

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try output.writeListOutput(fbs.writer(), &store);
    const result = fbs.getWritten();

    try std.testing.expectEqualStrings("APPLE\nBANANA\nMANGO\nZEBRA\n", result);
}
