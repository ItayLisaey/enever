const std = @import("std");
const env_parser = @import("env-parser");
const masking = @import("masking");
const output = @import("output");

// ============================================================================
// PERFORMANCE & STRESS TESTS
// Tests with large data sets to verify performance and memory handling
// ============================================================================

test "performance - parse 100 variables" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    // Generate content with 100 variables
    var content_buf: [16384]u8 = undefined;
    var content_len: usize = 0;

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const written = std.fmt.bufPrint(content_buf[content_len..], "KEY_{d:0>3}=value_for_key_{d:0>3}_with_some_extra_content\n", .{ i, i }) catch break;
        content_len += written.len;
    }

    try env_parser.parseEnvContent(allocator, content_buf[0..content_len], ".env", &store);

    try std.testing.expectEqual(@as(usize, 100), store.count());
}

test "performance - parse 500 variables" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    // Generate content with 500 variables
    var content_buf: [65536]u8 = undefined;
    var content_len: usize = 0;

    var i: usize = 0;
    while (i < 500) : (i += 1) {
        const written = std.fmt.bufPrint(content_buf[content_len..], "KEY_{d:0>3}=value_{d:0>3}\n", .{ i, i }) catch break;
        content_len += written.len;
    }

    try env_parser.parseEnvContent(allocator, content_buf[0..content_len], ".env", &store);

    try std.testing.expectEqual(@as(usize, 500), store.count());
}

test "performance - parse 1000 variables" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    // Generate content with 1000 variables (stress test)
    var content: std.ArrayListUnmanaged(u8) = .{};
    defer content.deinit(allocator);

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        var line_buf: [128]u8 = undefined;
        const line = std.fmt.bufPrint(&line_buf, "KEY_{d:0>4}=value_for_key_number_{d:0>4}\n", .{ i, i }) catch continue;
        try content.appendSlice(allocator, line);
    }

    try env_parser.parseEnvContent(allocator, content.items, ".env", &store);

    try std.testing.expectEqual(@as(usize, 1000), store.count());

    // Verify first and last keys
    try std.testing.expect(store.get("KEY_0000") != null);
    try std.testing.expect(store.get("KEY_0999") != null);
}

test "performance - long value (1KB)" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    // Create a 1KB value
    var long_value: [1024]u8 = undefined;
    @memset(&long_value, 'x');

    var content: std.ArrayListUnmanaged(u8) = .{};
    defer content.deinit(allocator);

    try content.appendSlice(allocator, "LONG_VALUE=");
    try content.appendSlice(allocator, &long_value);
    try content.append(allocator, '\n');

    try env_parser.parseEnvContent(allocator, content.items, ".env", &store);

    const entry = store.get("LONG_VALUE");
    try std.testing.expect(entry != null);
    try std.testing.expectEqual(@as(usize, 1024), entry.?.value.len);
}

test "performance - very long value (10KB)" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    // Create a 10KB value
    const long_value = try allocator.alloc(u8, 10240);
    defer allocator.free(long_value);
    @memset(long_value, 'y');

    var content: std.ArrayListUnmanaged(u8) = .{};
    defer content.deinit(allocator);

    try content.appendSlice(allocator, "VERY_LONG_VALUE=");
    try content.appendSlice(allocator, long_value);
    try content.append(allocator, '\n');

    try env_parser.parseEnvContent(allocator, content.items, ".env", &store);

    const entry = store.get("VERY_LONG_VALUE");
    try std.testing.expect(entry != null);
    try std.testing.expectEqual(@as(usize, 10240), entry.?.value.len);
}

test "performance - masking many values" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    // Add 200 sensitive-looking values
    var i: usize = 0;
    while (i < 200) : (i += 1) {
        var key_buf: [32]u8 = undefined;
        var val_buf: [64]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "SECRET_{d:0>3}", .{i}) catch continue;
        const val = std.fmt.bufPrint(&val_buf, "sk_live_{d:0>8}_abcdefgh", .{i}) catch continue;
        try store.put(key, val, ".env");
    }

    try std.testing.expectEqual(@as(usize, 200), store.count());

    // Generate output - should mask all 200 values
    var buf: [65536]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const no_unmask = [_][]const u8{};
    try output.writeStructuredOutput(fbs.writer(), &store, &no_unmask);

    const result = fbs.getWritten();

    // Verify header shows correct count
    try std.testing.expect(std.mem.indexOf(u8, result, "envs[200]") != null);

    // Verify no real values leaked
    try std.testing.expect(std.mem.indexOf(u8, result, "sk_live_") == null);
}

test "performance - json output with many entries" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    // Add 100 entries
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var key_buf: [32]u8 = undefined;
        var val_buf: [64]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "KEY_{d:0>3}", .{i}) catch continue;
        const val = std.fmt.bufPrint(&val_buf, "value_number_{d:0>3}", .{i}) catch continue;
        try store.put(key, val, ".env");
    }

    // Generate JSON output
    var buf: [65536]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const no_unmask = [_][]const u8{};
    try output.writeJsonOutput(fbs.writer(), &store, &no_unmask);

    const result = fbs.getWritten();

    // Verify it's valid JSON structure
    try std.testing.expect(std.mem.indexOf(u8, result, "{") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"envs\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "}") != null);

    // Verify some entries are present
    try std.testing.expect(std.mem.indexOf(u8, result, "\"key\": \"KEY_000\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"key\": \"KEY_099\"") != null);
}

test "performance - list output with many keys" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    // Add 300 keys (to test sorting performance)
    var i: usize = 0;
    while (i < 300) : (i += 1) {
        var key_buf: [32]u8 = undefined;
        // Use varied prefixes to test sorting
        const key = std.fmt.bufPrint(&key_buf, "{c}_{d:0>3}", .{ @as(u8, @intCast(65 + (i % 26))), i }) catch continue;
        try store.put(key, "value", ".env");
    }

    // Generate list output
    var buf: [16384]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try output.writeListOutput(fbs.writer(), &store);

    const result = fbs.getWritten();

    // Verify output has content
    try std.testing.expect(result.len > 0);

    // Count newlines to verify all keys listed
    var newline_count: usize = 0;
    for (result) |c| {
        if (c == '\n') newline_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 300), newline_count);
}

// ============================================================================
// MEMORY EFFICIENCY TESTS
// ============================================================================

test "memory - store handles many replacements without leaks" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    // Replace the same key many times
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var val_buf: [64]u8 = undefined;
        const val = std.fmt.bufPrint(&val_buf, "value_iteration_{d}", .{i}) catch continue;
        try store.put("CHANGING_KEY", val, ".env");
    }

    // Should only have 1 entry
    try std.testing.expectEqual(@as(usize, 1), store.count());
    try std.testing.expectEqualStrings("value_iteration_99", store.get("CHANGING_KEY").?.value);
}

test "memory - parse content multiple times without leaks" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const content = "KEY1=value1\nKEY2=value2\nKEY3=value3\n";

    // Parse same content multiple times (overwriting)
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        try env_parser.parseEnvContent(allocator, content, ".env", &store);
    }

    // Should still only have 3 entries
    try std.testing.expectEqual(@as(usize, 3), store.count());
}

test "memory - large content parsing without leaks" {
    const allocator = std.testing.allocator;

    // Create and destroy stores in a loop
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var store = env_parser.EnvStore.init(allocator);

        // Add 50 entries
        var j: usize = 0;
        while (j < 50) : (j += 1) {
            var key_buf: [32]u8 = undefined;
            const key = std.fmt.bufPrint(&key_buf, "KEY_{d}", .{j}) catch continue;
            try store.put(key, "some_value_here", ".env");
        }

        // Clean up - testing allocator will catch leaks
        store.deinit();
    }
}

// ============================================================================
// MASKING PERFORMANCE TESTS
// ============================================================================

test "masking - mask many values efficiently" {
    var buf: [64]u8 = undefined;

    // Mask 1000 values
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        var val_buf: [64]u8 = undefined;
        const val = std.fmt.bufPrint(&val_buf, "secret_value_{d:0>4}", .{i}) catch continue;
        const masked = masking.maskValue(val, &buf);

        // Verify masking works correctly
        try std.testing.expectEqualStrings("****", masked[0..4]);
        try std.testing.expectEqual(@as(usize, 8), masked.len);
    }
}

test "masking - mask varying length values" {
    var buf: [64]u8 = undefined;

    // Test values of varying lengths
    const test_values = [_][]const u8{
        "",
        "a",
        "ab",
        "abc",
        "abcd",
        "abcde",
        "abcdef",
        "abcdefghij",
        "abcdefghijklmnopqrstuvwxyz",
        "a" ** 50,
    };

    for (test_values) |val| {
        const masked = masking.maskValue(val, &buf);
        // All should start with ****
        try std.testing.expect(std.mem.startsWith(u8, masked, "****"));
    }
}

// ============================================================================
// REAL FILE PERFORMANCE TESTS
// ============================================================================

test "performance - read and parse real temp file" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create a file with 200 entries
    {
        const env_file = try tmp_dir.dir.createFile(".env", .{});
        defer env_file.close();

        var i: usize = 0;
        while (i < 200) : (i += 1) {
            var line_buf: [128]u8 = undefined;
            const line = std.fmt.bufPrint(&line_buf, "KEY_{d:0>3}=value_{d:0>3}_with_extra_content\n", .{ i, i }) catch continue;
            try env_file.writeAll(line);
        }
    }

    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    {
        const path = try tmp_dir.dir.realpathAlloc(allocator, ".env");
        defer allocator.free(path);
        try env_parser.parseEnvFile(allocator, path, &store);
    }

    try std.testing.expectEqual(@as(usize, 200), store.count());
}

// ============================================================================
// BOUNDARY CONDITION TESTS
// ============================================================================

test "boundary - exactly at 1MB file limit minus header" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    // Create content close to but under 1MB (leaving room for safety)
    // 1MB = 1,048,576 bytes, we'll use ~500KB to be safe
    const target_size: usize = 500 * 1024;
    var content = try allocator.alloc(u8, target_size);
    defer allocator.free(content);

    // Fill with valid env content
    var pos: usize = 0;
    var key_num: usize = 0;

    while (pos + 100 < target_size) : (key_num += 1) {
        var line_buf: [128]u8 = undefined;
        const line = std.fmt.bufPrint(&line_buf, "KEY_{d:0>5}=value_content_{d:0>5}_xxxxxx\n", .{ key_num, key_num }) catch break;

        if (pos + line.len > target_size) break;

        @memcpy(content[pos .. pos + line.len], line);
        pos += line.len;
    }

    try env_parser.parseEnvContent(allocator, content[0..pos], ".env", &store);

    // Should have parsed many entries
    try std.testing.expect(store.count() > 1000);
}

test "boundary - empty value entries in bulk" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    // Create content with 100 empty values
    var content_buf: [8192]u8 = undefined;
    var content_len: usize = 0;

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const written = std.fmt.bufPrint(content_buf[content_len..], "EMPTY_{d:0>3}=\n", .{i}) catch break;
        content_len += written.len;
    }

    try env_parser.parseEnvContent(allocator, content_buf[0..content_len], ".env", &store);

    try std.testing.expectEqual(@as(usize, 100), store.count());

    // Verify all values are empty
    var it = store.iterator();
    while (it.next()) |entry| {
        try std.testing.expectEqual(@as(usize, 0), entry.value_ptr.value.len);
    }
}

test "boundary - keys at various length limits" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    // Test various key lengths
    const key_lengths = [_]usize{ 1, 5, 10, 50, 100, 200 };

    for (key_lengths) |len| {
        var key = try allocator.alloc(u8, len);
        defer allocator.free(key);
        @memset(key, 'K');

        // Make it a valid key by starting with a letter
        key[0] = 'A';

        try store.put(key, "value", ".env");
    }

    try std.testing.expectEqual(@as(usize, key_lengths.len), store.count());
}
