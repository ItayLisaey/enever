const std = @import("std");
const env_parser = @import("env-parser");
const masking = @import("masking");
const output = @import("output");

// ============================================================================
// GET COMMAND TESTS
// ============================================================================

test "get single existing key" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("API_KEY", "secret123456789", ".env");

    // Verify key exists
    const entry = store.get("API_KEY");
    try std.testing.expect(entry != null);
    try std.testing.expectEqualStrings("secret123456789", entry.?.value);
}

test "get non-existent key returns null" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("EXISTING", "value", ".env");

    const entry = store.get("NON_EXISTENT");
    try std.testing.expect(entry == null);
}

test "get all keys - json format output" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("KEY1", "value1", ".env");
    try store.put("KEY2", "value2", ".env");

    var buf: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const unmask_keys = [_][]const u8{};
    try output.writeJsonOutput(fbs.writer(), &store, &unmask_keys);

    const result = fbs.getWritten();
    // Verify JSON structure
    try std.testing.expect(std.mem.indexOf(u8, result, "\"envs\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"key\": \"KEY1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"key\": \"KEY2\"") != null);
}

test "get all with unmask specific keys" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("API_KEY", "super_secret_key", ".env");
    try store.put("API_SECRET", "another_secret", ".env");

    var buf: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    // Unmask only API_KEY
    const unmask_keys = [_][]const u8{"API_KEY"};
    try output.writeStructuredOutput(fbs.writer(), &store, &unmask_keys);

    const result = fbs.getWritten();

    // API_KEY should be unmasked (public)
    try std.testing.expect(std.mem.indexOf(u8, result, "API_KEY,super_secret_key,public") != null);

    // API_SECRET should remain masked
    try std.testing.expect(std.mem.indexOf(u8, result, "API_SECRET,****cret,masked") != null);
}

test "get with multiple unmask keys" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("KEY1", "value1value1", ".env");
    try store.put("KEY2", "value2value2", ".env");
    try store.put("KEY3", "value3value3", ".env");

    var buf: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    // Unmask KEY1 and KEY3
    const unmask_keys = [_][]const u8{ "KEY1", "KEY3" };
    try output.writeStructuredOutput(fbs.writer(), &store, &unmask_keys);

    const result = fbs.getWritten();

    // KEY1 and KEY3 should be public
    try std.testing.expect(std.mem.indexOf(u8, result, "KEY1,value1value1,public") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "KEY3,value3value3,public") != null);

    // KEY2 should remain masked
    try std.testing.expect(std.mem.indexOf(u8, result, "KEY2,****lue2,masked") != null);
}

// ============================================================================
// SET COMMAND TESTS (via store manipulation)
// ============================================================================

test "set new key in store" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("NEW_KEY", "new_value", ".env.local");

    try std.testing.expectEqual(@as(usize, 1), store.count());
    try std.testing.expectEqualStrings("new_value", store.get("NEW_KEY").?.value);
    try std.testing.expectEqualStrings(".env.local", store.get("NEW_KEY").?.source_file);
}

test "set overwrites existing key" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("KEY", "original", ".env");
    try store.put("KEY", "updated", ".env.local");

    try std.testing.expectEqual(@as(usize, 1), store.count());
    try std.testing.expectEqualStrings("updated", store.get("KEY").?.value);
    try std.testing.expectEqualStrings(".env.local", store.get("KEY").?.source_file);
}

test "set with special characters in value" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("URL", "https://api.com?key=value&other=123", ".env.local");
    try store.put("JSON", "{\"key\": \"value\"}", ".env.local");

    try std.testing.expectEqualStrings("https://api.com?key=value&other=123", store.get("URL").?.value);
    try std.testing.expectEqualStrings("{\"key\": \"value\"}", store.get("JSON").?.value);
}

test "set with empty value" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("EMPTY", "", ".env.local");

    try std.testing.expectEqualStrings("", store.get("EMPTY").?.value);
}

// ============================================================================
// LIST COMMAND TESTS
// ============================================================================

test "list with no env files produces empty output" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try output.writeListOutput(fbs.writer(), &store);

    try std.testing.expectEqual(@as(usize, 0), fbs.getWritten().len);
}

test "list with many keys verifies alphabetical order" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("ZEBRA", "z", ".env");
    try store.put("APPLE", "a", ".env");
    try store.put("MANGO", "m", ".env");
    try store.put("BANANA", "b", ".env");
    try store.put("CHERRY", "c", ".env");

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try output.writeListOutput(fbs.writer(), &store);

    const result = fbs.getWritten();
    try std.testing.expectEqualStrings("APPLE\nBANANA\nCHERRY\nMANGO\nZEBRA\n", result);
}

test "list output contains only keys no values" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("API_KEY", "super_secret_value", ".env");
    try store.put("DB_PASSWORD", "database_password", ".env");

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try output.writeListOutput(fbs.writer(), &store);

    const result = fbs.getWritten();

    // Should contain keys
    try std.testing.expect(std.mem.indexOf(u8, result, "API_KEY") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "DB_PASSWORD") != null);

    // Should NOT contain values
    try std.testing.expect(std.mem.indexOf(u8, result, "super_secret_value") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "database_password") == null);
}

// ============================================================================
// RUN COMMAND TESTS (store preparation)
// ============================================================================

test "run command - env vars are loaded correctly" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("NODE_ENV", "production", ".env");
    try store.put("PORT", "3000", ".env");
    try store.put("DATABASE_URL", "postgres://localhost/db", ".env");

    // Verify all vars would be available for run command
    try std.testing.expectEqual(@as(usize, 3), store.count());
    try std.testing.expectEqualStrings("production", store.get("NODE_ENV").?.value);
    try std.testing.expectEqualStrings("3000", store.get("PORT").?.value);
    try std.testing.expectEqualStrings("postgres://localhost/db", store.get("DATABASE_URL").?.value);
}

// ============================================================================
// INIT COMMAND TESTS (store preparation)
// ============================================================================

test "init - keys are sorted alphabetically" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("Z_VAR", "z", ".env");
    try store.put("A_VAR", "a", ".env");
    try store.put("M_VAR", "m", ".env");

    // Collect and sort keys as init would do
    var keys: std.ArrayListUnmanaged([]const u8) = .{};
    defer keys.deinit(allocator);

    var it = store.iterator();
    while (it.next()) |entry| {
        try keys.append(allocator, entry.value_ptr.key);
    }

    std.mem.sort([]const u8, keys.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.lessThan);

    try std.testing.expectEqualStrings("A_VAR", keys.items[0]);
    try std.testing.expectEqualStrings("M_VAR", keys.items[1]);
    try std.testing.expectEqualStrings("Z_VAR", keys.items[2]);
}

// ============================================================================
// DIFF COMMAND TESTS (store comparison)
// ============================================================================

test "diff - detect key only in first mode" {
    const allocator = std.testing.allocator;

    var store1 = env_parser.EnvStore.init(allocator);
    defer store1.deinit();

    var store2 = env_parser.EnvStore.init(allocator);
    defer store2.deinit();

    try store1.put("SHARED", "value", ".env");
    try store1.put("ONLY_IN_DEV", "dev_value", ".env.development");

    try store2.put("SHARED", "value", ".env");

    // ONLY_IN_DEV exists in store1 but not store2
    try std.testing.expect(store1.get("ONLY_IN_DEV") != null);
    try std.testing.expect(store2.get("ONLY_IN_DEV") == null);
}

test "diff - detect key only in second mode" {
    const allocator = std.testing.allocator;

    var store1 = env_parser.EnvStore.init(allocator);
    defer store1.deinit();

    var store2 = env_parser.EnvStore.init(allocator);
    defer store2.deinit();

    try store1.put("SHARED", "value", ".env");

    try store2.put("SHARED", "value", ".env");
    try store2.put("ONLY_IN_PROD", "prod_value", ".env.production");

    // ONLY_IN_PROD exists in store2 but not store1
    try std.testing.expect(store1.get("ONLY_IN_PROD") == null);
    try std.testing.expect(store2.get("ONLY_IN_PROD") != null);
}

test "diff - detect different values for same key" {
    const allocator = std.testing.allocator;

    var store1 = env_parser.EnvStore.init(allocator);
    defer store1.deinit();

    var store2 = env_parser.EnvStore.init(allocator);
    defer store2.deinit();

    try store1.put("DEBUG", "true", ".env.development");
    try store2.put("DEBUG", "false", ".env.production");

    // Same key, different values
    const val1 = store1.get("DEBUG").?.value;
    const val2 = store2.get("DEBUG").?.value;
    try std.testing.expect(!std.mem.eql(u8, val1, val2));
}

test "diff - identical environments" {
    const allocator = std.testing.allocator;

    var store1 = env_parser.EnvStore.init(allocator);
    defer store1.deinit();

    var store2 = env_parser.EnvStore.init(allocator);
    defer store2.deinit();

    try store1.put("KEY1", "value1", ".env");
    try store1.put("KEY2", "value2", ".env");

    try store2.put("KEY1", "value1", ".env");
    try store2.put("KEY2", "value2", ".env");

    // Both stores should have same keys with same values
    try std.testing.expectEqualStrings(store1.get("KEY1").?.value, store2.get("KEY1").?.value);
    try std.testing.expectEqualStrings(store1.get("KEY2").?.value, store2.get("KEY2").?.value);
}

// ============================================================================
// VALIDATE COMMAND TESTS
// ============================================================================

test "validate - all required vars present" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("DATABASE_URL", "postgres://localhost/db", ".env");
    try store.put("API_KEY", "my-api-key", ".env");
    try store.put("SECRET", "my-secret", ".env");

    const required_vars = [_][]const u8{ "DATABASE_URL", "API_KEY", "SECRET" };

    // Check all required vars exist
    for (required_vars) |var_name| {
        try std.testing.expect(store.get(var_name) != null);
    }
}

test "validate - missing required var" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("DATABASE_URL", "postgres://localhost/db", ".env");
    // Missing API_KEY

    const required_vars = [_][]const u8{ "DATABASE_URL", "API_KEY" };

    var missing: std.ArrayListUnmanaged([]const u8) = .{};
    defer missing.deinit(allocator);

    for (required_vars) |var_name| {
        if (store.get(var_name) == null) {
            try missing.append(allocator, var_name);
        }
    }

    try std.testing.expectEqual(@as(usize, 1), missing.items.len);
    try std.testing.expectEqualStrings("API_KEY", missing.items[0]);
}

test "validate - empty required var detected" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("DATABASE_URL", "postgres://localhost/db", ".env");
    try store.put("API_KEY", "", ".env"); // Empty!

    const required_vars = [_][]const u8{ "DATABASE_URL", "API_KEY" };

    var empty: std.ArrayListUnmanaged([]const u8) = .{};
    defer empty.deinit(allocator);

    for (required_vars) |var_name| {
        if (store.get(var_name)) |entry| {
            if (entry.value.len == 0) {
                try empty.append(allocator, var_name);
            }
        }
    }

    try std.testing.expectEqual(@as(usize, 1), empty.items.len);
    try std.testing.expectEqualStrings("API_KEY", empty.items[0]);
}

// ============================================================================
// SINGLE VALUE OUTPUT TESTS
// ============================================================================

test "single value output - masked" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("SECRET", "my_super_secret_value", ".env");

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try output.writeSingleValue(fbs.writer(), store.get("SECRET").?, false, false);

    const result = fbs.getWritten();
    // Should be masked
    try std.testing.expect(std.mem.indexOf(u8, result, "****") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "[masked]") != null);
    // Should NOT contain full value
    try std.testing.expect(std.mem.indexOf(u8, result, "my_super_secret_value") == null);
}

test "single value output - unmasked" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("SECRET", "my_super_secret_value", ".env");

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try output.writeSingleValue(fbs.writer(), store.get("SECRET").?, true, false);

    const result = fbs.getWritten();
    // Should contain full value
    try std.testing.expect(std.mem.indexOf(u8, result, "my_super_secret_value") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "[public]") != null);
}

test "single value output - json format masked" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("KEY", "secret_value", ".env");

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try output.writeSingleValue(fbs.writer(), store.get("KEY").?, false, true);

    const result = fbs.getWritten();
    // Should be JSON
    try std.testing.expect(std.mem.indexOf(u8, result, "{") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"key\": \"KEY\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"status\": \"masked\"") != null);
}

test "single value output - json format unmasked" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("KEY", "secret_value", ".env");

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try output.writeSingleValue(fbs.writer(), store.get("KEY").?, true, true);

    const result = fbs.getWritten();
    // Should be JSON with public status
    try std.testing.expect(std.mem.indexOf(u8, result, "\"status\": \"public\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "secret_value") != null);
}

// ============================================================================
// CLI ARGUMENT PARSING TESTS
// ============================================================================

const cli = @import("cli");

test "parseArgsFromSlice handles get with flag after command" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{ "get", "--json" };
    var opts = try cli.parseArgsFromSlice(allocator, &args);
    defer opts.deinit();

    try std.testing.expectEqual(cli.Command.get, opts.command);
    try std.testing.expect(opts.json_format == true);
    try std.testing.expect(opts.key == null);
}

test "parseArgsFromSlice handles get KEY --json" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{ "get", "API_KEY", "--json" };
    var opts = try cli.parseArgsFromSlice(allocator, &args);
    defer opts.deinit();

    try std.testing.expectEqual(cli.Command.get, opts.command);
    try std.testing.expect(opts.json_format == true);
    try std.testing.expectEqualStrings("API_KEY", opts.key.?);
}

test "parseArgsFromSlice handles get -u KEY" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{ "get", "-u", "SECRET_KEY" };
    var opts = try cli.parseArgsFromSlice(allocator, &args);
    defer opts.deinit();

    try std.testing.expectEqual(cli.Command.get, opts.command);
    try std.testing.expectEqual(@as(usize, 1), opts.unmask_keys.items.len);
    try std.testing.expectEqualStrings("SECRET_KEY", opts.unmask_keys.items[0]);
}

test "parseArgsFromSlice handles flags before command" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{ "--json", "get", "API_KEY" };
    var opts = try cli.parseArgsFromSlice(allocator, &args);
    defer opts.deinit();

    try std.testing.expectEqual(cli.Command.get, opts.command);
    try std.testing.expect(opts.json_format == true);
    try std.testing.expectEqualStrings("API_KEY", opts.key.?);
}

test "parseArgsFromSlice handles multiple flags with get" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{ "get", "--json", "-q", "-u", "SECRET" };
    var opts = try cli.parseArgsFromSlice(allocator, &args);
    defer opts.deinit();

    try std.testing.expectEqual(cli.Command.get, opts.command);
    try std.testing.expect(opts.json_format == true);
    try std.testing.expect(opts.quiet == true);
    try std.testing.expectEqual(@as(usize, 1), opts.unmask_keys.items.len);
    try std.testing.expectEqualStrings("SECRET", opts.unmask_keys.items[0]);
}

test "parseArgsFromSlice handles list command" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{"list"};
    var opts = try cli.parseArgsFromSlice(allocator, &args);
    defer opts.deinit();

    try std.testing.expectEqual(cli.Command.list, opts.command);
}

test "parseArgsFromSlice handles set command" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{ "set", "KEY=value" };
    var opts = try cli.parseArgsFromSlice(allocator, &args);
    defer opts.deinit();

    try std.testing.expectEqual(cli.Command.set, opts.command);
    try std.testing.expectEqualStrings("KEY", opts.key.?);
    try std.testing.expectEqualStrings("value", opts.value.?);
}

test "parseArgsFromSlice returns error for invalid set format" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{ "set", "INVALID_NO_EQUALS" };
    const result = cli.parseArgsFromSlice(allocator, &args);
    try std.testing.expectError(error.InvalidSetFormat, result);
}

test "parseArgsFromSlice returns error for missing set argument" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{"set"};
    const result = cli.parseArgsFromSlice(allocator, &args);
    try std.testing.expectError(error.MissingSetArgument, result);
}

test "parseArgsFromSlice returns error for missing unmask key" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{ "get", "-u" };
    const result = cli.parseArgsFromSlice(allocator, &args);
    try std.testing.expectError(error.MissingUnmaskKey, result);
}

test "parseArgsFromSlice returns error for unknown flag" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{"--unknown-flag"};
    const result = cli.parseArgsFromSlice(allocator, &args);
    try std.testing.expectError(error.UnknownFlag, result);
}
