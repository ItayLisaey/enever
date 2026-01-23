const std = @import("std");
const masking = @import("masking.zig");
const env_parser = @import("env-parser.zig");

pub const OutputFormat = enum {
    structured, // LLM-optimized header-first format
    json, // Standard JSON output
};

// File-based output functions for CLI
pub fn writeStructuredOutputToFile(
    file: std.fs.File,
    store: *const env_parser.EnvStore,
    unmask_keys: []const []const u8,
) !void {
    const count = store.count();

    // Write header
    var header_buf: [64]u8 = undefined;
    const header = std.fmt.bufPrint(&header_buf, "envs[{d}]{{key,value,status}}:\n", .{count}) catch return error.OutOfMemory;
    try file.writeAll(header);

    // Collect entries for consistent ordering
    var entries: std.ArrayListUnmanaged(env_parser.EnvEntry) = .{};
    defer entries.deinit(store.allocator);

    var it = store.iterator();
    while (it.next()) |entry| {
        try entries.append(store.allocator, entry.value_ptr.*);
    }

    // Sort by key for consistent output
    std.mem.sort(env_parser.EnvEntry, entries.items, {}, struct {
        fn lessThan(_: void, a: env_parser.EnvEntry, b: env_parser.EnvEntry) bool {
            return std.mem.lessThan(u8, a.key, b.key);
        }
    }.lessThan);

    // Write entries
    var mask_buf: [64]u8 = undefined;
    var line_buf: [1024]u8 = undefined;
    for (entries.items) |entry| {
        const should_unmask = for (unmask_keys) |uk| {
            if (std.mem.eql(u8, uk, entry.key)) break true;
        } else false;

        const display_value = if (entry.mask_status == .masked and !should_unmask)
            masking.maskValue(entry.value, &mask_buf)
        else
            entry.value;

        const status_str = if (entry.mask_status == .masked and !should_unmask)
            "masked"
        else
            "public";

        const line = std.fmt.bufPrint(&line_buf, "  {s},{s},{s}\n", .{ entry.key, display_value, status_str }) catch continue;
        try file.writeAll(line);
    }
}

pub fn writeJsonOutputToFile(
    file: std.fs.File,
    store: *const env_parser.EnvStore,
    unmask_keys: []const []const u8,
) !void {
    // Collect entries for consistent ordering
    var entries: std.ArrayListUnmanaged(env_parser.EnvEntry) = .{};
    defer entries.deinit(store.allocator);

    var it = store.iterator();
    while (it.next()) |entry| {
        try entries.append(store.allocator, entry.value_ptr.*);
    }

    // Sort by key for consistent output
    std.mem.sort(env_parser.EnvEntry, entries.items, {}, struct {
        fn lessThan(_: void, a: env_parser.EnvEntry, b: env_parser.EnvEntry) bool {
            return std.mem.lessThan(u8, a.key, b.key);
        }
    }.lessThan);

    try file.writeAll("{\n  \"envs\": [\n");

    var mask_buf: [64]u8 = undefined;
    var line_buf: [2048]u8 = undefined;
    for (entries.items, 0..) |entry, i| {
        const should_unmask = for (unmask_keys) |uk| {
            if (std.mem.eql(u8, uk, entry.key)) break true;
        } else false;

        const display_value = if (entry.mask_status == .masked and !should_unmask)
            masking.maskValue(entry.value, &mask_buf)
        else
            entry.value;

        const status_str = if (entry.mask_status == .masked and !should_unmask)
            "masked"
        else
            "public";

        // Escape value for JSON
        var escaped_buf: [1024]u8 = undefined;
        const escaped_value = escapeJsonString(display_value, &escaped_buf);

        const comma = if (i < entries.items.len - 1) "," else "";
        const line = std.fmt.bufPrint(&line_buf, "    {{\"key\": \"{s}\", \"value\": \"{s}\", \"status\": \"{s}\"}}{s}\n", .{ entry.key, escaped_value, status_str, comma }) catch continue;
        try file.writeAll(line);
    }

    try file.writeAll("  ]\n}\n");
}

fn escapeJsonString(input: []const u8, buf: []u8) []const u8 {
    var i: usize = 0;
    for (input) |c| {
        if (i + 2 >= buf.len) break;
        switch (c) {
            '"' => {
                buf[i] = '\\';
                buf[i + 1] = '"';
                i += 2;
            },
            '\\' => {
                buf[i] = '\\';
                buf[i + 1] = '\\';
                i += 2;
            },
            '\n' => {
                buf[i] = '\\';
                buf[i + 1] = 'n';
                i += 2;
            },
            '\r' => {
                buf[i] = '\\';
                buf[i + 1] = 'r';
                i += 2;
            },
            '\t' => {
                buf[i] = '\\';
                buf[i + 1] = 't';
                i += 2;
            },
            else => {
                buf[i] = c;
                i += 1;
            },
        }
    }
    return buf[0..i];
}

pub fn writeListOutputToFile(file: std.fs.File, store: *const env_parser.EnvStore) !void {
    // Collect keys for consistent ordering
    var keys: std.ArrayListUnmanaged([]const u8) = .{};
    defer keys.deinit(store.allocator);

    var it = store.iterator();
    while (it.next()) |entry| {
        try keys.append(store.allocator, entry.value_ptr.key);
    }

    // Sort keys
    std.mem.sort([]const u8, keys.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    var buf: [512]u8 = undefined;
    for (keys.items) |key| {
        const line = std.fmt.bufPrint(&buf, "{s}\n", .{key}) catch continue;
        try file.writeAll(line);
    }
}

pub fn writeSingleValueToFile(
    file: std.fs.File,
    entry: env_parser.EnvEntry,
    unmask: bool,
    json_format: bool,
) !void {
    var mask_buf: [64]u8 = undefined;
    const display_value = if (entry.mask_status == .masked and !unmask)
        masking.maskValue(entry.value, &mask_buf)
    else
        entry.value;

    const status_str = if (entry.mask_status == .masked and !unmask)
        "masked"
    else
        "public";

    var buf: [2048]u8 = undefined;
    if (json_format) {
        var escaped_buf: [1024]u8 = undefined;
        const escaped_value = escapeJsonString(display_value, &escaped_buf);
        const line = std.fmt.bufPrint(&buf, "{{\"key\": \"{s}\", \"value\": \"{s}\", \"status\": \"{s}\"}}\n", .{ entry.key, escaped_value, status_str }) catch return error.OutOfMemory;
        try file.writeAll(line);
    } else {
        const line = std.fmt.bufPrint(&buf, "{s}={s} [{s}]\n", .{ entry.key, display_value, status_str }) catch return error.OutOfMemory;
        try file.writeAll(line);
    }
}

// Generic writer-based functions for tests
pub fn writeStructuredOutput(
    writer: anytype,
    store: *const env_parser.EnvStore,
    unmask_keys: []const []const u8,
) !void {
    const count = store.count();

    // Write header
    try writer.print("envs[{d}]{{key,value,status}}:\n", .{count});

    // Collect entries for consistent ordering
    var entries: std.ArrayListUnmanaged(env_parser.EnvEntry) = .{};
    defer entries.deinit(store.allocator);

    var it = store.iterator();
    while (it.next()) |entry| {
        try entries.append(store.allocator, entry.value_ptr.*);
    }

    // Sort by key for consistent output
    std.mem.sort(env_parser.EnvEntry, entries.items, {}, struct {
        fn lessThan(_: void, a: env_parser.EnvEntry, b: env_parser.EnvEntry) bool {
            return std.mem.lessThan(u8, a.key, b.key);
        }
    }.lessThan);

    // Write entries
    var mask_buf: [64]u8 = undefined;
    for (entries.items) |entry| {
        const should_unmask = for (unmask_keys) |uk| {
            if (std.mem.eql(u8, uk, entry.key)) break true;
        } else false;

        const display_value = if (entry.mask_status == .masked and !should_unmask)
            masking.maskValue(entry.value, &mask_buf)
        else
            entry.value;

        const status_str = if (entry.mask_status == .masked and !should_unmask)
            "masked"
        else
            "public";

        try writer.print("  {s},{s},{s}\n", .{ entry.key, display_value, status_str });
    }
}

pub fn writeJsonOutput(
    writer: anytype,
    store: *const env_parser.EnvStore,
    unmask_keys: []const []const u8,
) !void {
    // Collect entries for consistent ordering
    var entries: std.ArrayListUnmanaged(env_parser.EnvEntry) = .{};
    defer entries.deinit(store.allocator);

    var it = store.iterator();
    while (it.next()) |entry| {
        try entries.append(store.allocator, entry.value_ptr.*);
    }

    // Sort by key for consistent output
    std.mem.sort(env_parser.EnvEntry, entries.items, {}, struct {
        fn lessThan(_: void, a: env_parser.EnvEntry, b: env_parser.EnvEntry) bool {
            return std.mem.lessThan(u8, a.key, b.key);
        }
    }.lessThan);

    try writer.writeAll("{\n  \"envs\": [\n");

    var mask_buf: [64]u8 = undefined;
    for (entries.items, 0..) |entry, i| {
        const should_unmask = for (unmask_keys) |uk| {
            if (std.mem.eql(u8, uk, entry.key)) break true;
        } else false;

        const display_value = if (entry.mask_status == .masked and !should_unmask)
            masking.maskValue(entry.value, &mask_buf)
        else
            entry.value;

        const status_str = if (entry.mask_status == .masked and !should_unmask)
            "masked"
        else
            "public";

        try writer.writeAll("    {");
        try writer.print("\"key\": \"{s}\", ", .{entry.key});
        try writeJsonString(writer, "value", display_value);
        try writer.print(", \"status\": \"{s}\"", .{status_str});
        try writer.writeAll("}");

        if (i < entries.items.len - 1) {
            try writer.writeAll(",");
        }
        try writer.writeAll("\n");
    }

    try writer.writeAll("  ]\n}\n");
}

fn writeJsonString(writer: anytype, key: []const u8, value: []const u8) !void {
    try writer.print("\"{s}\": \"", .{key});
    for (value) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(c),
        }
    }
    try writer.writeAll("\"");
}

pub fn writeListOutput(writer: anytype, store: *const env_parser.EnvStore) !void {
    // Collect keys for consistent ordering
    var keys: std.ArrayListUnmanaged([]const u8) = .{};
    defer keys.deinit(store.allocator);

    var it = store.iterator();
    while (it.next()) |entry| {
        try keys.append(store.allocator, entry.value_ptr.key);
    }

    // Sort keys
    std.mem.sort([]const u8, keys.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    for (keys.items) |key| {
        try writer.print("{s}\n", .{key});
    }
}

pub fn writeSingleValue(
    writer: anytype,
    entry: env_parser.EnvEntry,
    unmask: bool,
    json_format: bool,
) !void {
    var mask_buf: [64]u8 = undefined;
    const display_value = if (entry.mask_status == .masked and !unmask)
        masking.maskValue(entry.value, &mask_buf)
    else
        entry.value;

    const status_str = if (entry.mask_status == .masked and !unmask)
        "masked"
    else
        "public";

    if (json_format) {
        try writer.writeAll("{");
        try writer.print("\"key\": \"{s}\", ", .{entry.key});
        try writeJsonString(writer, "value", display_value);
        try writer.print(", \"status\": \"{s}\"", .{status_str});
        try writer.writeAll("}\n");
    } else {
        try writer.print("{s}={s} [{s}]\n", .{ entry.key, display_value, status_str });
    }
}

// =============================================================================
// Multi-file TOON format output (new format - shows all files)
// =============================================================================

/// Check if a TOON value needs quoting
fn needsToonQuote(value: []const u8) bool {
    if (value.len == 0) return true;

    // Check for leading/trailing whitespace
    if (value[0] == ' ' or value[0] == '\t') return true;
    if (value[value.len - 1] == ' ' or value[value.len - 1] == '\t') return true;

    // Check for reserved words
    if (std.mem.eql(u8, value, "true") or
        std.mem.eql(u8, value, "false") or
        std.mem.eql(u8, value, "null"))
    {
        return true;
    }

    // Check for special characters that require quoting
    for (value) |c| {
        switch (c) {
            ':', '"', '\\', '[', ']', '{', '}', ',', '\n', '\r', '\t' => return true,
            else => {},
        }
    }

    // Check if it looks like a number
    if (looksLikeNumber(value)) return true;

    return false;
}

fn looksLikeNumber(value: []const u8) bool {
    if (value.len == 0) return false;

    var i: usize = 0;

    // Optional leading minus
    if (value[i] == '-') {
        i += 1;
        if (i >= value.len) return false;
    }

    // Must start with digit
    if (value[i] < '0' or value[i] > '9') return false;

    // Rest can be digits or decimal point
    var has_dot = false;
    while (i < value.len) : (i += 1) {
        const c = value[i];
        if (c >= '0' and c <= '9') continue;
        if (c == '.' and !has_dot) {
            has_dot = true;
            continue;
        }
        return false;
    }

    return true;
}

/// Write a TOON-quoted string if needed
fn writeToonValue(writer: anytype, value: []const u8) !void {
    if (needsToonQuote(value)) {
        try writer.writeByte('"');
        for (value) |c| {
            switch (c) {
                '"' => try writer.writeAll("\\\""),
                '\\' => try writer.writeAll("\\\\"),
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                else => try writer.writeByte(c),
            }
        }
        try writer.writeByte('"');
    } else {
        try writer.writeAll(value);
    }
}

/// Write all env vars in TOON format (multi-file, shows values from each file)
pub fn writeMultiToonOutput(
    writer: anytype,
    store: *const env_parser.MultiEnvStore,
    unmask_keys: []const []const u8,
) !void {
    // Collect and sort keys
    var keys: std.ArrayListUnmanaged([]const u8) = .{};
    defer keys.deinit(store.allocator);

    var it = store.iterator();
    while (it.next()) |entry| {
        try keys.append(store.allocator, entry.value_ptr.key);
    }

    std.mem.sort([]const u8, keys.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    var mask_buf: [64]u8 = undefined;

    for (keys.items) |key| {
        const entry = store.get(key).?;

        // Key line
        try writer.print("{s}:\n", .{key});

        // Check if this key should be unmasked
        const should_unmask = for (unmask_keys) |uk| {
            if (std.mem.eql(u8, uk, key)) break true;
        } else false;

        // Values from each file (indented with 2 spaces per TOON spec)
        for (entry.values.items) |fv| {
            const display_value = if (fv.mask_status == .masked and !should_unmask)
                masking.maskValue(fv.value, &mask_buf)
            else
                fv.value;

            try writer.print("  {s}: ", .{fv.source_file});
            try writeToonValue(writer, display_value);
            try writer.writeByte('\n');
        }
    }
}

/// Write a single key's values in TOON format (no key header, just file: value lines)
pub fn writeMultiToonSingleKey(
    writer: anytype,
    entry: env_parser.MultiEnvEntry,
    unmask: bool,
) !void {
    var mask_buf: [64]u8 = undefined;

    for (entry.values.items) |fv| {
        const display_value = if (fv.mask_status == .masked and !unmask)
            masking.maskValue(fv.value, &mask_buf)
        else
            fv.value;

        try writer.print("{s}: ", .{fv.source_file});
        try writeToonValue(writer, display_value);
        try writer.writeByte('\n');
    }
}

/// Write all env vars in JSON format (multi-file)
pub fn writeMultiJsonOutput(
    writer: anytype,
    store: *const env_parser.MultiEnvStore,
    unmask_keys: []const []const u8,
) !void {
    // Collect and sort keys
    var keys: std.ArrayListUnmanaged([]const u8) = .{};
    defer keys.deinit(store.allocator);

    var it = store.iterator();
    while (it.next()) |entry| {
        try keys.append(store.allocator, entry.value_ptr.key);
    }

    std.mem.sort([]const u8, keys.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    var mask_buf: [64]u8 = undefined;

    try writer.writeAll("{\n");

    for (keys.items, 0..) |key, key_idx| {
        const entry = store.get(key).?;

        const should_unmask = for (unmask_keys) |uk| {
            if (std.mem.eql(u8, uk, key)) break true;
        } else false;

        try writer.print("  \"{s}\": [\n", .{key});

        for (entry.values.items, 0..) |fv, val_idx| {
            const display_value = if (fv.mask_status == .masked and !should_unmask)
                masking.maskValue(fv.value, &mask_buf)
            else
                fv.value;

            try writer.print("    {{\"file\": \"{s}\", \"value\": \"", .{fv.source_file});
            // Write escaped JSON value directly
            for (display_value) |c| {
                switch (c) {
                    '"' => try writer.writeAll("\\\""),
                    '\\' => try writer.writeAll("\\\\"),
                    '\n' => try writer.writeAll("\\n"),
                    '\r' => try writer.writeAll("\\r"),
                    '\t' => try writer.writeAll("\\t"),
                    else => try writer.writeByte(c),
                }
            }
            try writer.writeAll("\"}");

            if (val_idx < entry.values.items.len - 1) {
                try writer.writeAll(",");
            }
            try writer.writeAll("\n");
        }

        try writer.writeAll("  ]");
        if (key_idx < keys.items.len - 1) {
            try writer.writeAll(",");
        }
        try writer.writeAll("\n");
    }

    try writer.writeAll("}\n");
}

/// Write a single key's values in JSON format (multi-file)
pub fn writeMultiJsonSingleKey(
    writer: anytype,
    entry: env_parser.MultiEnvEntry,
    unmask: bool,
) !void {
    var mask_buf: [64]u8 = undefined;

    try writer.writeAll("[\n");

    for (entry.values.items, 0..) |fv, i| {
        const display_value = if (fv.mask_status == .masked and !unmask)
            masking.maskValue(fv.value, &mask_buf)
        else
            fv.value;

        try writer.print("  {{\"file\": \"{s}\", \"value\": \"", .{fv.source_file});
        // Escape value
        for (display_value) |c| {
            switch (c) {
                '"' => try writer.writeAll("\\\""),
                '\\' => try writer.writeAll("\\\\"),
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                else => try writer.writeByte(c),
            }
        }
        try writer.writeAll("\"}");

        if (i < entry.values.items.len - 1) {
            try writer.writeAll(",");
        }
        try writer.writeAll("\n");
    }

    try writer.writeAll("]\n");
}

/// Write list of keys (multi-file store)
pub fn writeMultiListOutput(writer: anytype, store: *const env_parser.MultiEnvStore) !void {
    var keys: std.ArrayListUnmanaged([]const u8) = .{};
    defer keys.deinit(store.allocator);

    var it = store.iterator();
    while (it.next()) |entry| {
        try keys.append(store.allocator, entry.value_ptr.key);
    }

    std.mem.sort([]const u8, keys.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    for (keys.items) |key| {
        try writer.print("{s}\n", .{key});
    }
}

// =============================================================================
// File-based wrappers for multi-file output
// Uses dynamic ArrayListUnmanaged buffer to support arbitrary output sizes
// =============================================================================

pub fn writeMultiToonOutputToFile(
    file: std.fs.File,
    store: *const env_parser.MultiEnvStore,
    unmask_keys: []const []const u8,
) !void {
    var buffer: std.ArrayListUnmanaged(u8) = .{};
    defer buffer.deinit(store.allocator);
    try writeMultiToonOutput(buffer.writer(store.allocator), store, unmask_keys);
    try file.writeAll(buffer.items);
}

pub fn writeMultiToonSingleKeyToFile(
    file: std.fs.File,
    entry: env_parser.MultiEnvEntry,
    unmask: bool,
) !void {
    // Single key output is bounded, use fixed buffer
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try writeMultiToonSingleKey(fbs.writer(), entry, unmask);
    try file.writeAll(fbs.getWritten());
}

pub fn writeMultiJsonOutputToFile(
    file: std.fs.File,
    store: *const env_parser.MultiEnvStore,
    unmask_keys: []const []const u8,
) !void {
    var buffer: std.ArrayListUnmanaged(u8) = .{};
    defer buffer.deinit(store.allocator);
    try writeMultiJsonOutput(buffer.writer(store.allocator), store, unmask_keys);
    try file.writeAll(buffer.items);
}

pub fn writeMultiJsonSingleKeyToFile(
    file: std.fs.File,
    entry: env_parser.MultiEnvEntry,
    unmask: bool,
) !void {
    // Single key output is bounded, use fixed buffer
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try writeMultiJsonSingleKey(fbs.writer(), entry, unmask);
    try file.writeAll(fbs.getWritten());
}

pub fn writeMultiListOutputToFile(file: std.fs.File, store: *const env_parser.MultiEnvStore) !void {
    var buffer: std.ArrayListUnmanaged(u8) = .{};
    defer buffer.deinit(store.allocator);
    try writeMultiListOutput(buffer.writer(store.allocator), store);
    try file.writeAll(buffer.items);
}

// =============================================================================
// Tests
// =============================================================================

test "toon quoting" {
    // Empty string needs quotes
    try std.testing.expect(needsToonQuote(""));

    // Reserved words need quotes
    try std.testing.expect(needsToonQuote("true"));
    try std.testing.expect(needsToonQuote("false"));
    try std.testing.expect(needsToonQuote("null"));

    // Numbers need quotes
    try std.testing.expect(needsToonQuote("123"));
    try std.testing.expect(needsToonQuote("-45.6"));

    // Special chars need quotes
    try std.testing.expect(needsToonQuote("hello:world"));
    try std.testing.expect(needsToonQuote("has\"quote"));

    // Normal strings don't need quotes
    try std.testing.expect(!needsToonQuote("hello"));
    try std.testing.expect(!needsToonQuote("api_key_123"));

    // URLs contain colons, so they need quotes
    try std.testing.expect(needsToonQuote("https://example.com"));
}

test "multi toon output format" {
    const allocator = std.testing.allocator;
    var store = env_parser.MultiEnvStore.init(allocator);
    defer store.deinit();

    try store.put("API_KEY", "dev_secret", ".env");
    try store.put("API_KEY", "prod_secret", ".env.production");

    var buf: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    const unmask_keys = [_][]const u8{};
    try writeMultiToonOutput(fbs.writer(), &store, &unmask_keys);

    const output_str = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output_str, "API_KEY:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output_str, "  .env: ") != null);
    try std.testing.expect(std.mem.indexOf(u8, output_str, "  .env.production: ") != null);
}

// Tests
test "structured output format" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("API_URL", "https://api.example.com", ".env");
    try store.put("API_KEY", "sk_live_secret123", ".env");

    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    const unmask_keys = [_][]const u8{};
    try writeStructuredOutput(fbs.writer(), &store, &unmask_keys);

    const output_str = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output_str, "envs[2]{key,value,status}:") != null);
    // All values masked by default
    try std.testing.expect(std.mem.indexOf(u8, output_str, "API_URL,****.com,masked") != null);
    try std.testing.expect(std.mem.indexOf(u8, output_str, "API_KEY,****t123,masked") != null);
}

test "json output format" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("PORT", "3000", ".env");

    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    const unmask_keys = [_][]const u8{};
    try writeJsonOutput(fbs.writer(), &store, &unmask_keys);

    const output_str = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output_str, "\"envs\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output_str, "\"key\": \"PORT\"") != null);
    // All values masked
    try std.testing.expect(std.mem.indexOf(u8, output_str, "\"status\": \"masked\"") != null);
}

test "list output" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("KEY_B", "value_b", ".env");
    try store.put("KEY_A", "value_a", ".env");

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    try writeListOutput(fbs.writer(), &store);

    const output_str = fbs.getWritten();
    // Keys should be sorted
    try std.testing.expectEqualStrings("KEY_A\nKEY_B\n", output_str);
}

test "unmask override" {
    const allocator = std.testing.allocator;
    var store = env_parser.EnvStore.init(allocator);
    defer store.deinit();

    try store.put("API_KEY", "sk_live_secret123", ".env");

    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    const unmask_keys = [_][]const u8{"API_KEY"};
    try writeStructuredOutput(fbs.writer(), &store, &unmask_keys);

    const output_str = fbs.getWritten();
    // Value should be unmasked
    try std.testing.expect(std.mem.indexOf(u8, output_str, "API_KEY,sk_live_secret123,public") != null);
}

test "multi json output produces valid json structure" {
    const allocator = std.testing.allocator;
    var store = env_parser.MultiEnvStore.init(allocator);
    defer store.deinit();

    try store.put("API_KEY", "secret_value_123", ".env");
    try store.put("API_KEY", "prod_secret_456", ".env.production");

    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const no_unmask = [_][]const u8{};
    try writeMultiJsonOutput(fbs.writer(), &store, &no_unmask);

    const result = fbs.getWritten();

    // Should NOT contain malformed pattern "value": "v":
    try std.testing.expect(std.mem.indexOf(u8, result, "\"value\": \"v\":") == null);
    // Should contain properly formatted JSON
    try std.testing.expect(std.mem.indexOf(u8, result, "\"value\": \"****") != null);
    try std.testing.expect(std.mem.startsWith(u8, result, "{"));
    try std.testing.expect(result[result.len - 2] == '}');
}

test "multi json output escapes special characters" {
    const allocator = std.testing.allocator;
    var store = env_parser.MultiEnvStore.init(allocator);
    defer store.deinit();

    try store.put("SPECIAL", "line1\nline2\ttab\"quote\\backslash", ".env");

    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const unmask_keys = [_][]const u8{"SPECIAL"};
    try writeMultiJsonOutput(fbs.writer(), &store, &unmask_keys);

    const result = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, result, "\\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\\t") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\\\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\\\\") != null);
}

test "multi json single key produces valid json array" {
    const allocator = std.testing.allocator;
    var store = env_parser.MultiEnvStore.init(allocator);
    defer store.deinit();

    try store.put("DB_URL", "postgres://localhost/dev", ".env");
    try store.put("DB_URL", "postgres://prod/app", ".env.production");

    const entry = store.get("DB_URL").?;

    var buf: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try writeMultiJsonSingleKey(fbs.writer(), entry, true);

    const result = fbs.getWritten();
    try std.testing.expect(std.mem.startsWith(u8, result, "["));
    try std.testing.expect(std.mem.indexOf(u8, result, "\"file\": \".env\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"value\": \"postgres://") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"value\": \"v\":") == null);
}

test "multi output handles large number of env vars" {
    const allocator = std.testing.allocator;
    var store = env_parser.MultiEnvStore.init(allocator);
    defer store.deinit();

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var key_buf: [64]u8 = undefined;
        var val_buf: [128]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "VARIABLE_WITH_LONG_NAME_{d}", .{i}) catch unreachable;
        const val = std.fmt.bufPrint(&val_buf, "this_is_a_somewhat_long_value_for_testing_purposes_{d}", .{i}) catch unreachable;
        try store.put(key, val, ".env");
        try store.put(key, val, ".env.production");
    }

    var buf: [65536]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const no_unmask = [_][]const u8{};
    try writeMultiToonOutput(fbs.writer(), &store, &no_unmask);

    const result = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, result, "VARIABLE_WITH_LONG_NAME_0:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "VARIABLE_WITH_LONG_NAME_99:") != null);
}
