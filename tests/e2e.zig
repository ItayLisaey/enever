const std = @import("std");
const env_parser = @import("env-parser");
const masking = @import("masking");
const output = @import("output");

// ============================================================================
// END-TO-END WORKFLOW TESTS
// Tests that simulate complete user workflows with real file operations
// ============================================================================

test "e2e - complete workflow: create, load, output" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Step 1: Create .env file (simulating user creating their env file)
    {
        const env_file = try tmp_dir.dir.createFile(".env", .{});
        try env_file.writeAll(
            \\# Database configuration
            \\DATABASE_URL=postgres://localhost:5432/mydb
            \\DATABASE_POOL_SIZE=10
            \\
            \\# API settings
            \\API_URL=https://api.example.com
            \\API_KEY=sk_live_1234567890abcdef
            \\
            \\# Feature flags
            \\DEBUG=false
            \\
        );
        env_file.close();
    }

    // Step 2: Load and parse the file
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    {
        const path = try tmp_dir.dir.realpathAlloc(allocator, ".env");
        defer allocator.free(path);
        try env_parser.parseEnvFile(allocator, path, &store);
    }

    // Step 3: Verify all keys were loaded
    try std.testing.expectEqual(@as(usize, 5), store.count());

    // Step 4: Generate structured output
    {
        var buf: [4096]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        const no_unmask = [_][]const u8{};
        try output.writeStructuredOutput(fbs.writer(), &store, &no_unmask);

        const result = fbs.getWritten();

        // Verify header
        try std.testing.expect(std.mem.indexOf(u8, result, "envs[5]{key,value,status}:") != null);

        // Verify all keys are present
        try std.testing.expect(std.mem.indexOf(u8, result, "API_KEY") != null);
        try std.testing.expect(std.mem.indexOf(u8, result, "API_URL") != null);
        try std.testing.expect(std.mem.indexOf(u8, result, "DATABASE_URL") != null);

        // Verify values are masked
        try std.testing.expect(std.mem.indexOf(u8, result, "sk_live_1234567890abcdef") == null);
    }
}

test "e2e - mode switching workflow" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create base .env
    {
        const env_file = try tmp_dir.dir.createFile(".env", .{});
        try env_file.writeAll("API_URL=https://api.example.com\nDEBUG=false\n");
        env_file.close();
    }

    // Create .env.development
    {
        const dev_file = try tmp_dir.dir.createFile(".env.development", .{});
        try dev_file.writeAll("API_URL=http://localhost:3000\nDEBUG=true\n");
        dev_file.close();
    }

    // Create .env.production
    {
        const prod_file = try tmp_dir.dir.createFile(".env.production", .{});
        try prod_file.writeAll("API_URL=https://api.prod.example.com\nDEBUG=false\n");
        prod_file.close();
    }

    // Test development mode
    {
        var store = env_parser.EnvStore.init(allocator);
        defer store.deinit();

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

        try std.testing.expectEqualStrings("http://localhost:3000", store.get("API_URL").?.value);
        try std.testing.expectEqualStrings("true", store.get("DEBUG").?.value);
    }

    // Test production mode
    {
        var store = env_parser.EnvStore.init(allocator);
        defer store.deinit();

        {
            const path = try tmp_dir.dir.realpathAlloc(allocator, ".env");
            defer allocator.free(path);
            try env_parser.parseEnvFile(allocator, path, &store);
        }
        {
            const path = try tmp_dir.dir.realpathAlloc(allocator, ".env.production");
            defer allocator.free(path);
            try env_parser.parseEnvFile(allocator, path, &store);
        }

        try std.testing.expectEqualStrings("https://api.prod.example.com", store.get("API_URL").?.value);
        try std.testing.expectEqualStrings("false", store.get("DEBUG").?.value);
    }
}

test "e2e - local override workflow" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Team's shared .env
    {
        const env_file = try tmp_dir.dir.createFile(".env", .{});
        try env_file.writeAll("DATABASE_URL=postgres://shared-db:5432/app\nAPI_KEY=shared_key\n");
        env_file.close();
    }

    // Developer's personal .env.local (gitignored)
    {
        const local_file = try tmp_dir.dir.createFile(".env.local", .{});
        try local_file.writeAll("DATABASE_URL=postgres://localhost:5432/dev\nAPI_KEY=my_personal_key\n");
        local_file.close();
    }

    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    // Load in priority order
    {
        const path = try tmp_dir.dir.realpathAlloc(allocator, ".env");
        defer allocator.free(path);
        try env_parser.parseEnvFile(allocator, path, &store);
    }
    {
        const path = try tmp_dir.dir.realpathAlloc(allocator, ".env.local");
        defer allocator.free(path);
        try env_parser.parseEnvFile(allocator, path, &store);
    }

    // Local values should be used
    try std.testing.expectEqualStrings("postgres://localhost:5432/dev", store.get("DATABASE_URL").?.value);
    try std.testing.expectEqualStrings("my_personal_key", store.get("API_KEY").?.value);
}

test "e2e - list keys workflow" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create env file with many keys
    {
        const env_file = try tmp_dir.dir.createFile(".env", .{});
        try env_file.writeAll(
            \\ZEBRA_KEY=secret1
            \\ALPHA_KEY=secret2
            \\MIDDLE_KEY=secret3
            \\BETA_KEY=secret4
            \\
        );
        env_file.close();
    }

    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    {
        const path = try tmp_dir.dir.realpathAlloc(allocator, ".env");
        defer allocator.free(path);
        try env_parser.parseEnvFile(allocator, path, &store);
    }

    // Generate list output
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try output.writeListOutput(fbs.writer(), &store);

    const result = fbs.getWritten();

    // Verify keys are listed alphabetically
    try std.testing.expectEqualStrings("ALPHA_KEY\nBETA_KEY\nMIDDLE_KEY\nZEBRA_KEY\n", result);

    // Verify NO secrets are leaked
    try std.testing.expect(std.mem.indexOf(u8, result, "secret") == null);
}

test "e2e - json output workflow" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    {
        const env_file = try tmp_dir.dir.createFile(".env", .{});
        try env_file.writeAll("KEY1=value1\nKEY2=value2\n");
        env_file.close();
    }

    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    {
        const path = try tmp_dir.dir.realpathAlloc(allocator, ".env");
        defer allocator.free(path);
        try env_parser.parseEnvFile(allocator, path, &store);
    }

    // Generate JSON output
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const no_unmask = [_][]const u8{};
    try output.writeJsonOutput(fbs.writer(), &store, &no_unmask);

    const result = fbs.getWritten();

    // Verify it's valid JSON-like structure
    try std.testing.expect(std.mem.indexOf(u8, result, "{") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"envs\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "}") != null);

    // Verify keys are present
    try std.testing.expect(std.mem.indexOf(u8, result, "\"key\": \"KEY1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"key\": \"KEY2\"") != null);
}

test "e2e - unmask specific key workflow" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    {
        const env_file = try tmp_dir.dir.createFile(".env", .{});
        try env_file.writeAll("PUBLIC_URL=https://example.com\nSECRET_KEY=super_secret_12345\n");
        env_file.close();
    }

    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    {
        const path = try tmp_dir.dir.realpathAlloc(allocator, ".env");
        defer allocator.free(path);
        try env_parser.parseEnvFile(allocator, path, &store);
    }

    // Unmask PUBLIC_URL only
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const unmask_keys = [_][]const u8{"PUBLIC_URL"};
    try output.writeStructuredOutput(fbs.writer(), &store, &unmask_keys);

    const result = fbs.getWritten();

    // PUBLIC_URL should be visible
    try std.testing.expect(std.mem.indexOf(u8, result, "https://example.com") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "PUBLIC_URL,https://example.com,public") != null);

    // SECRET_KEY should NOT be visible
    try std.testing.expect(std.mem.indexOf(u8, result, "super_secret_12345") == null);
}

// ============================================================================
// REAL FILE I/O TESTS
// ============================================================================

test "e2e - file not found handling" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    const result = env_parser.parseEnvFile(allocator, "/nonexistent/path/.env", &store);
    try std.testing.expectError(env_parser.ParseError.FileNotFound, result);
}

test "e2e - empty file handling" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create empty file
    const env_file = try tmp_dir.dir.createFile(".env", .{});
    env_file.close();

    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    {
        const path = try tmp_dir.dir.realpathAlloc(allocator, ".env");
        defer allocator.free(path);
        try env_parser.parseEnvFile(allocator, path, &store);
    }

    try std.testing.expectEqual(@as(usize, 0), store.count());
}

test "e2e - file with only comments" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    {
        const env_file = try tmp_dir.dir.createFile(".env", .{});
        try env_file.writeAll(
            \\# This is a comment
            \\# Another comment
            \\### Header ###
            \\
            \\# More comments
            \\
        );
        env_file.close();
    }

    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    {
        const path = try tmp_dir.dir.realpathAlloc(allocator, ".env");
        defer allocator.free(path);
        try env_parser.parseEnvFile(allocator, path, &store);
    }

    try std.testing.expectEqual(@as(usize, 0), store.count());
}

// ============================================================================
// DIFF WORKFLOW TESTS
// ============================================================================

test "e2e - diff between environments" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create development environment
    {
        const dev_file = try tmp_dir.dir.createFile(".env.development", .{});
        try dev_file.writeAll("API_URL=http://localhost:3000\nDEBUG=true\nDEV_ONLY=value\n");
        dev_file.close();
    }

    // Create production environment
    {
        const prod_file = try tmp_dir.dir.createFile(".env.production", .{});
        try prod_file.writeAll("API_URL=https://api.prod.com\nDEBUG=false\nPROD_ONLY=value\n");
        prod_file.close();
    }

    // Load development
    var dev_store = env_parser.EnvStore.init(allocator);
    defer dev_store.deinit();
    {
        const path = try tmp_dir.dir.realpathAlloc(allocator, ".env.development");
        defer allocator.free(path);
        try env_parser.parseEnvFile(allocator, path, &dev_store);
    }

    // Load production
    var prod_store = env_parser.EnvStore.init(allocator);
    defer prod_store.deinit();
    {
        const path = try tmp_dir.dir.realpathAlloc(allocator, ".env.production");
        defer allocator.free(path);
        try env_parser.parseEnvFile(allocator, path, &prod_store);
    }

    // Compare: API_URL and DEBUG differ, DEV_ONLY only in dev, PROD_ONLY only in prod
    try std.testing.expect(!std.mem.eql(u8, dev_store.get("API_URL").?.value, prod_store.get("API_URL").?.value));
    try std.testing.expect(!std.mem.eql(u8, dev_store.get("DEBUG").?.value, prod_store.get("DEBUG").?.value));
    try std.testing.expect(dev_store.get("DEV_ONLY") != null);
    try std.testing.expect(prod_store.get("DEV_ONLY") == null);
    try std.testing.expect(dev_store.get("PROD_ONLY") == null);
    try std.testing.expect(prod_store.get("PROD_ONLY") != null);
}

// ============================================================================
// VALIDATION WORKFLOW TESTS
// ============================================================================

test "e2e - validate required variables" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    {
        const env_file = try tmp_dir.dir.createFile(".env", .{});
        try env_file.writeAll("DATABASE_URL=postgres://localhost/db\nAPI_KEY=my_key\nEMPTY_VAR=\n");
        env_file.close();
    }

    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    {
        const path = try tmp_dir.dir.realpathAlloc(allocator, ".env");
        defer allocator.free(path);
        try env_parser.parseEnvFile(allocator, path, &store);
    }

    // Define required variables
    const required_vars = [_][]const u8{ "DATABASE_URL", "API_KEY", "MISSING_VAR", "EMPTY_VAR" };

    var missing: std.ArrayListUnmanaged([]const u8) = .{};
    defer missing.deinit(allocator);

    var empty: std.ArrayListUnmanaged([]const u8) = .{};
    defer empty.deinit(allocator);

    for (required_vars) |var_name| {
        if (store.get(var_name)) |entry| {
            if (entry.value.len == 0) {
                try empty.append(allocator, var_name);
            }
        } else {
            try missing.append(allocator, var_name);
        }
    }

    // MISSING_VAR should be missing
    try std.testing.expectEqual(@as(usize, 1), missing.items.len);
    try std.testing.expectEqualStrings("MISSING_VAR", missing.items[0]);

    // EMPTY_VAR should be in empty list
    try std.testing.expectEqual(@as(usize, 1), empty.items.len);
    try std.testing.expectEqualStrings("EMPTY_VAR", empty.items[0]);
}

// ============================================================================
// COMPLEX VALUE TESTS
// ============================================================================

test "e2e - complex real-world values" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    {
        const env_file = try tmp_dir.dir.createFile(".env", .{});
        try env_file.writeAll(
            \\# Database
            \\DATABASE_URL=postgres://user:pass@host:5432/db?ssl=true&pool=10
            \\
            \\# AWS
            \\AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
            \\AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
            \\
            \\# OAuth
            \\GOOGLE_CLIENT_ID=123456789-abc.apps.googleusercontent.com
            \\
            \\# Feature flags as JSON
            \\FEATURES={"dark_mode":true,"beta_features":false}
            \\
            \\# Connection string
            \\REDIS_URL=redis://:password@localhost:6379/0
            \\
        );
        env_file.close();
    }

    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    {
        const path = try tmp_dir.dir.realpathAlloc(allocator, ".env");
        defer allocator.free(path);
        try env_parser.parseEnvFile(allocator, path, &store);
    }

    // Verify complex values are preserved
    try std.testing.expectEqualStrings("postgres://user:pass@host:5432/db?ssl=true&pool=10", store.get("DATABASE_URL").?.value);
    try std.testing.expectEqualStrings("AKIAIOSFODNN7EXAMPLE", store.get("AWS_ACCESS_KEY_ID").?.value);
    try std.testing.expectEqualStrings("{\"dark_mode\":true,\"beta_features\":false}", store.get("FEATURES").?.value);
    try std.testing.expectEqualStrings("redis://:password@localhost:6379/0", store.get("REDIS_URL").?.value);
}

test "e2e - quoted values with special characters" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    {
        const env_file = try tmp_dir.dir.createFile(".env", .{});
        try env_file.writeAll(
            \\DOUBLE_QUOTED="value with spaces"
            \\SINGLE_QUOTED='another value'
            \\WITH_EQUALS="key=value&other=123"
            \\WITH_HASH="path/to/file#anchor"
            \\
        );
        env_file.close();
    }

    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    {
        const path = try tmp_dir.dir.realpathAlloc(allocator, ".env");
        defer allocator.free(path);
        try env_parser.parseEnvFile(allocator, path, &store);
    }

    try std.testing.expectEqualStrings("value with spaces", store.get("DOUBLE_QUOTED").?.value);
    try std.testing.expectEqualStrings("another value", store.get("SINGLE_QUOTED").?.value);
    try std.testing.expectEqualStrings("key=value&other=123", store.get("WITH_EQUALS").?.value);
    try std.testing.expectEqualStrings("path/to/file#anchor", store.get("WITH_HASH").?.value);
}

// ============================================================================
// OUTPUT FORMAT CONSISTENCY TESTS
// ============================================================================

test "e2e - structured and json output have same data" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("KEY1", "value1", ".env");
    try store.put("KEY2", "value2", ".env");

    // Get structured output
    var struct_buf: [4096]u8 = undefined;
    var struct_fbs = std.io.fixedBufferStream(&struct_buf);
    const no_unmask = [_][]const u8{};
    try output.writeStructuredOutput(struct_fbs.writer(), &store, &no_unmask);
    const struct_result = struct_fbs.getWritten();

    // Get JSON output
    var json_buf: [4096]u8 = undefined;
    var json_fbs = std.io.fixedBufferStream(&json_buf);
    try output.writeJsonOutput(json_fbs.writer(), &store, &no_unmask);
    const json_result = json_fbs.getWritten();

    // Both should have KEY1 and KEY2
    try std.testing.expect(std.mem.indexOf(u8, struct_result, "KEY1") != null);
    try std.testing.expect(std.mem.indexOf(u8, struct_result, "KEY2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_result, "KEY1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_result, "KEY2") != null);

    // Both should have masked status
    try std.testing.expect(std.mem.indexOf(u8, struct_result, "masked") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_result, "masked") != null);
}
