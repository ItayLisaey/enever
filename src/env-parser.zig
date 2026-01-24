const std = @import("std");
const masking = @import("masking.zig");

/// A single value from one env file
pub const FileValue = struct {
    source_file: []const u8,
    value: []const u8,
    mask_status: masking.MaskStatus,

    pub fn deinit(self: *FileValue, allocator: std.mem.Allocator) void {
        // Zero-fill value before freeing for security
        const value_ptr: [*]u8 = @constCast(self.value.ptr);
        @memset(value_ptr[0..self.value.len], 0);
        allocator.free(self.value);
        allocator.free(self.source_file);
    }
};

/// An env key with values from multiple files
pub const MultiEnvEntry = struct {
    key: []const u8,
    values: std.ArrayListUnmanaged(FileValue),

    pub fn deinit(self: *MultiEnvEntry, allocator: std.mem.Allocator) void {
        for (self.values.items) |*fv| {
            fv.deinit(allocator);
        }
        self.values.deinit(allocator);
        allocator.free(self.key);
    }
};

/// Store that keeps all values from all env files (no merging)
pub const MultiEnvStore = struct {
    entries: std.StringHashMap(MultiEnvEntry),
    files: std.ArrayListUnmanaged([]const u8), // List of discovered files in order
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MultiEnvStore {
        return .{
            .entries = std.StringHashMap(MultiEnvEntry).init(allocator),
            .files = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MultiEnvStore) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.entries.deinit();
        for (self.files.items) |f| {
            self.allocator.free(f);
        }
        self.files.deinit(self.allocator);
    }

    pub fn addFile(self: *MultiEnvStore, filename: []const u8) !void {
        const owned = try self.allocator.dupe(u8, filename);
        try self.files.append(self.allocator, owned);
    }

    pub fn put(self: *MultiEnvStore, key: []const u8, value: []const u8, source_file: []const u8) !void {
        const owned_value = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(owned_value);

        const owned_source = try self.allocator.dupe(u8, source_file);
        errdefer self.allocator.free(owned_source);

        const mask_status = masking.getMaskStatus(key);

        const file_value = FileValue{
            .source_file = owned_source,
            .value = owned_value,
            .mask_status = mask_status,
        };

        if (self.entries.getPtr(key)) |entry| {
            try entry.values.append(self.allocator, file_value);
        } else {
            const owned_key = try self.allocator.dupe(u8, key);
            errdefer self.allocator.free(owned_key);

            var values: std.ArrayListUnmanaged(FileValue) = .{};
            try values.append(self.allocator, file_value);

            try self.entries.put(owned_key, .{
                .key = owned_key,
                .values = values,
            });
        }
    }

    pub fn get(self: *const MultiEnvStore, key: []const u8) ?MultiEnvEntry {
        return self.entries.get(key);
    }

    pub fn count(self: *const MultiEnvStore) usize {
        return self.entries.count();
    }

    pub fn iterator(self: *const MultiEnvStore) std.StringHashMap(MultiEnvEntry).Iterator {
        return self.entries.iterator();
    }
};

// Legacy single-value entry (kept for compatibility)
pub const EnvEntry = struct {
    key: []const u8,
    value: []const u8,
    source_file: []const u8,
    mask_status: masking.MaskStatus,

    pub fn deinit(self: *EnvEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.key);
        // Zero-fill value before freeing for security
        const value_ptr: [*]u8 = @constCast(self.value.ptr);
        @memset(value_ptr[0..self.value.len], 0);
        allocator.free(self.value);
        allocator.free(self.source_file);
    }
};

// Legacy store (kept for compatibility)
pub const EnvStore = struct {
    entries: std.StringHashMap(EnvEntry),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) EnvStore {
        return .{
            .entries = std.StringHashMap(EnvEntry).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *EnvStore) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            var e = entry.value_ptr.*;
            e.deinit(self.allocator);
        }
        self.entries.deinit();
    }

    pub fn put(self: *EnvStore, key: []const u8, value: []const u8, source_file: []const u8) !void {
        const owned_key = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(owned_key);

        const owned_value = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(owned_value);

        const owned_source = try self.allocator.dupe(u8, source_file);
        errdefer self.allocator.free(owned_source);

        const mask_status = masking.getMaskStatus(key);

        // If key exists, free the old entry first
        if (self.entries.fetchRemove(owned_key)) |old| {
            var old_entry = old.value;
            old_entry.deinit(self.allocator);
        }

        try self.entries.put(owned_key, .{
            .key = owned_key,
            .value = owned_value,
            .source_file = owned_source,
            .mask_status = mask_status,
        });
    }

    pub fn get(self: *const EnvStore, key: []const u8) ?EnvEntry {
        return self.entries.get(key);
    }

    pub fn count(self: *const EnvStore) usize {
        return self.entries.count();
    }

    pub fn iterator(self: *const EnvStore) std.StringHashMap(EnvEntry).Iterator {
        return self.entries.iterator();
    }
};

pub const ParseError = error{
    InvalidFormat,
    OutOfMemory,
    FileNotFound,
    AccessDenied,
    Unexpected,
    IsDir,
    SystemResources,
    InvalidUtf8,
    LockViolation,
    InputOutput,
    BrokenPipe,
    ConnectionResetByPeer,
    ConnectionTimedOut,
    NotOpenForReading,
    SocketNotConnected,
    WouldBlock,
    OperationAborted,
    DiskQuota,
    FileTooBig,
    NoSpaceLeft,
    DeviceBusy,
    NoDevice,
    NetworkError,
    AntivirusInterference,
};

pub fn parseEnvFile(allocator: std.mem.Allocator, path: []const u8, store: *EnvStore) ParseError!void {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        return switch (err) {
            error.FileNotFound => error.FileNotFound,
            error.AccessDenied => error.AccessDenied,
            error.IsDir => error.IsDir,
            else => error.Unexpected,
        };
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.Unexpected,
        };
    };
    defer allocator.free(content);

    try parseEnvContent(allocator, content, path, store);
}

pub fn parseEnvContent(allocator: std.mem.Allocator, content: []const u8, source_file: []const u8, store: *EnvStore) ParseError!void {
    var i: usize = 0;

    while (i < content.len) {
        // Skip whitespace and find start of line
        while (i < content.len and (content[i] == ' ' or content[i] == '\t' or content[i] == '\r' or content[i] == '\n')) {
            i += 1;
        }
        if (i >= content.len) break;

        // Skip comments
        if (content[i] == '#') {
            while (i < content.len and content[i] != '\n') {
                i += 1;
            }
            continue;
        }

        // Find the = separator
        const line_start = i;
        var eq_pos: ?usize = null;
        while (i < content.len and content[i] != '\n' and content[i] != '=') {
            i += 1;
        }
        if (i >= content.len or content[i] == '\n') {
            // No = found on this line, skip it
            continue;
        }
        eq_pos = i;
        i += 1; // Skip the '='

        const key = std.mem.trim(u8, content[line_start..eq_pos.?], " \t\r");
        if (key.len == 0) {
            // Skip to end of line
            while (i < content.len and content[i] != '\n') {
                i += 1;
            }
            continue;
        }

        // Skip whitespace after =
        while (i < content.len and (content[i] == ' ' or content[i] == '\t')) {
            i += 1;
        }

        // Parse the value
        var value: []const u8 = undefined;
        if (i < content.len and (content[i] == '"' or content[i] == '\'')) {
            // Quoted value - find matching closing quote
            const quote_char = content[i];
            i += 1; // Skip opening quote
            const value_start = i;

            // Find closing quote, handling escaped quotes and newlines
            while (i < content.len) {
                if (content[i] == quote_char) {
                    // Check if it's escaped
                    var backslash_count: usize = 0;
                    var j = i;
                    while (j > value_start and content[j - 1] == '\\') {
                        backslash_count += 1;
                        j -= 1;
                    }
                    if (backslash_count % 2 == 0) {
                        // Not escaped, this is the closing quote
                        break;
                    }
                }
                i += 1;
            }

            value = content[value_start..i];
            if (i < content.len) {
                i += 1; // Skip closing quote
            }
        } else {
            // Unquoted value - read until end of line
            const value_start = i;
            while (i < content.len and content[i] != '\n') {
                i += 1;
            }
            value = std.mem.trimRight(u8, content[value_start..i], " \t\r");
        }

        // Store the value (need to process escape sequences for quoted values)
        const processed_value = try processEscapeSequences(allocator, value);
        defer allocator.free(processed_value);

        store.put(key, processed_value, source_file) catch return error.OutOfMemory;
    }
}

/// Process escape sequences in a string (like \n, \t, \\)
fn processEscapeSequences(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    // First pass: count the output size
    var output_len: usize = 0;
    var j: usize = 0;
    while (j < input.len) {
        if (input[j] == '\\' and j + 1 < input.len) {
            const next = input[j + 1];
            if (next == 'n' or next == 't' or next == 'r' or next == '\\' or next == '"' or next == '\'') {
                output_len += 1;
                j += 2;
                continue;
            }
        }
        output_len += 1;
        j += 1;
    }

    // Second pass: build the output
    const output = try allocator.alloc(u8, output_len);
    var out_idx: usize = 0;
    j = 0;
    while (j < input.len) {
        if (input[j] == '\\' and j + 1 < input.len) {
            const next = input[j + 1];
            switch (next) {
                'n' => {
                    output[out_idx] = '\n';
                    out_idx += 1;
                    j += 2;
                    continue;
                },
                't' => {
                    output[out_idx] = '\t';
                    out_idx += 1;
                    j += 2;
                    continue;
                },
                'r' => {
                    output[out_idx] = '\r';
                    out_idx += 1;
                    j += 2;
                    continue;
                },
                '\\' => {
                    output[out_idx] = '\\';
                    out_idx += 1;
                    j += 2;
                    continue;
                },
                '"' => {
                    output[out_idx] = '"';
                    out_idx += 1;
                    j += 2;
                    continue;
                },
                '\'' => {
                    output[out_idx] = '\'';
                    out_idx += 1;
                    j += 2;
                    continue;
                },
                else => {},
            }
        }
        output[out_idx] = input[j];
        out_idx += 1;
        j += 1;
    }

    return output;
}

/// Check if a filename matches env file patterns (.env, .env.*, +.env, +.env.*)
fn isEnvFile(name: []const u8) bool {
    // Match .env or +.env
    if (std.mem.eql(u8, name, ".env") or std.mem.eql(u8, name, "+.env")) {
        return true;
    }
    // Match .env.* (e.g., .env.local, .env.production)
    if (std.mem.startsWith(u8, name, ".env.") and name.len > 5) {
        return true;
    }
    // Match +.env.* (e.g., +.env.local, +.env.production)
    if (std.mem.startsWith(u8, name, "+.env.") and name.len > 6) {
        return true;
    }
    return false;
}

/// Check if file is a "base" env file (.env or +.env) for sorting priority
fn isBaseEnvFile(name: []const u8) bool {
    return std.mem.eql(u8, name, ".env") or std.mem.eql(u8, name, "+.env");
}

/// Discover all .env* and +.env* files in the current directory
pub fn discoverEnvFiles(allocator: std.mem.Allocator) !std.ArrayListUnmanaged([]const u8) {
    var files: std.ArrayListUnmanaged([]const u8) = .{};
    errdefer {
        for (files.items) |f| allocator.free(f);
        files.deinit(allocator);
    }

    var dir = std.fs.cwd().openDir(".", .{ .iterate = true }) catch |err| {
        return switch (err) {
            error.AccessDenied => error.AccessDenied,
            else => error.Unexpected,
        };
    };
    defer dir.close();

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind != .file) continue;

        if (isEnvFile(entry.name)) {
            const owned = try allocator.dupe(u8, entry.name);
            try files.append(allocator, owned);
        }
    }

    // Sort files: base env files first (.env, +.env), then others alphabetically
    std.mem.sort([]const u8, files.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            // Base env files always come first
            if (isBaseEnvFile(a) and !isBaseEnvFile(b)) return true;
            if (!isBaseEnvFile(a) and isBaseEnvFile(b)) return false;
            // Then alphabetically
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    return files;
}

/// Load all .env* files into a MultiEnvStore (no merging - keeps all values)
pub fn loadAllEnvFiles(allocator: std.mem.Allocator) !MultiEnvStore {
    var store = MultiEnvStore.init(allocator);
    errdefer store.deinit();

    var files = try discoverEnvFiles(allocator);
    defer {
        for (files.items) |f| allocator.free(f);
        files.deinit(allocator);
    }

    for (files.items) |filename| {
        try store.addFile(filename);
        parseEnvFileMulti(allocator, filename, &store) catch |err| {
            if (err != error.FileNotFound) return err;
        };
    }

    return store;
}

/// Load env files from a specific path (file or directory)
pub fn loadEnvFilesFromPath(allocator: std.mem.Allocator, path: []const u8) !MultiEnvStore {
    var store = MultiEnvStore.init(allocator);
    errdefer store.deinit();

    // Check if path is a file or directory
    const stat = std.fs.cwd().statFile(path) catch |err| {
        return switch (err) {
            error.FileNotFound => error.FileNotFound,
            error.AccessDenied => error.AccessDenied,
            else => error.Unexpected,
        };
    };

    if (stat.kind == .directory) {
        // It's a directory - discover .env* files in it
        var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| {
            return switch (err) {
                error.AccessDenied => error.AccessDenied,
                else => error.Unexpected,
            };
        };
        defer dir.close();

        var files: std.ArrayListUnmanaged([]const u8) = .{};
        defer {
            for (files.items) |f| allocator.free(f);
            files.deinit(allocator);
        }

        var iter = dir.iterate();
        while (iter.next() catch null) |entry| {
            if (entry.kind != .file) continue;
            if (isEnvFile(entry.name)) {
                const owned = try allocator.dupe(u8, entry.name);
                try files.append(allocator, owned);
            }
        }

        // Sort files: base env files first, then others alphabetically
        std.mem.sort([]const u8, files.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                if (isBaseEnvFile(a) and !isBaseEnvFile(b)) return true;
                if (!isBaseEnvFile(a) and isBaseEnvFile(b)) return false;
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);

        // Parse each file
        for (files.items) |filename| {
            try store.addFile(filename);
            // Build full path
            var path_buf: [4096]u8 = undefined;
            const full_path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ path, filename }) catch continue;
            parseEnvFileAtPath(allocator, full_path, filename, &store) catch |err| {
                if (err != error.FileNotFound) return err;
            };
        }
    } else {
        // It's a file - parse it directly
        const basename = std.fs.path.basename(path);
        try store.addFile(basename);
        parseEnvFileAtPath(allocator, path, basename, &store) catch |err| {
            if (err != error.FileNotFound) return err;
        };
    }

    return store;
}

/// Parse env file at an absolute/relative path into MultiEnvStore
fn parseEnvFileAtPath(allocator: std.mem.Allocator, path: []const u8, display_name: []const u8, store: *MultiEnvStore) ParseError!void {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        return switch (err) {
            error.FileNotFound => error.FileNotFound,
            error.AccessDenied => error.AccessDenied,
            error.IsDir => error.IsDir,
            else => error.Unexpected,
        };
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.Unexpected,
        };
    };
    defer allocator.free(content);

    try parseEnvContentMulti(content, display_name, store);
}

/// Parse env file into MultiEnvStore
pub fn parseEnvFileMulti(allocator: std.mem.Allocator, path: []const u8, store: *MultiEnvStore) ParseError!void {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        return switch (err) {
            error.FileNotFound => error.FileNotFound,
            error.AccessDenied => error.AccessDenied,
            error.IsDir => error.IsDir,
            else => error.Unexpected,
        };
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.Unexpected,
        };
    };
    defer allocator.free(content);

    try parseEnvContentMulti(content, path, store);
}

/// Parse env content into MultiEnvStore
pub fn parseEnvContentMulti(content: []const u8, source_file: []const u8, store: *MultiEnvStore) ParseError!void {
    var i: usize = 0;

    while (i < content.len) {
        // Skip whitespace and find start of line
        while (i < content.len and (content[i] == ' ' or content[i] == '\t' or content[i] == '\r' or content[i] == '\n')) {
            i += 1;
        }
        if (i >= content.len) break;

        // Skip comments
        if (content[i] == '#') {
            while (i < content.len and content[i] != '\n') {
                i += 1;
            }
            continue;
        }

        // Find the = separator
        const line_start = i;
        var eq_pos: ?usize = null;
        while (i < content.len and content[i] != '\n' and content[i] != '=') {
            i += 1;
        }
        if (i >= content.len or content[i] == '\n') {
            // No = found on this line, skip it
            continue;
        }
        eq_pos = i;
        i += 1; // Skip the '='

        const key = std.mem.trim(u8, content[line_start..eq_pos.?], " \t\r");
        if (key.len == 0) {
            // Skip to end of line
            while (i < content.len and content[i] != '\n') {
                i += 1;
            }
            continue;
        }

        // Skip whitespace after =
        while (i < content.len and (content[i] == ' ' or content[i] == '\t')) {
            i += 1;
        }

        // Parse the value
        var value: []const u8 = undefined;
        if (i < content.len and (content[i] == '"' or content[i] == '\'')) {
            // Quoted value - find matching closing quote
            const quote_char = content[i];
            i += 1; // Skip opening quote
            const value_start = i;

            // Find closing quote, handling escaped quotes and newlines
            while (i < content.len) {
                if (content[i] == quote_char) {
                    // Check if it's escaped
                    var backslash_count: usize = 0;
                    var j = i;
                    while (j > value_start and content[j - 1] == '\\') {
                        backslash_count += 1;
                        j -= 1;
                    }
                    if (backslash_count % 2 == 0) {
                        // Not escaped, this is the closing quote
                        break;
                    }
                }
                i += 1;
            }

            value = content[value_start..i];
            if (i < content.len) {
                i += 1; // Skip closing quote
            }
        } else {
            // Unquoted value - read until end of line
            const value_start = i;
            while (i < content.len and content[i] != '\n') {
                i += 1;
            }
            value = std.mem.trimRight(u8, content[value_start..i], " \t\r");
        }

        // Store the value (need to process escape sequences for quoted values)
        const processed_value = processEscapeSequences(store.allocator, value) catch return error.OutOfMemory;
        defer store.allocator.free(processed_value);

        store.put(key, processed_value, source_file) catch return error.OutOfMemory;
    }
}

// Legacy function kept for compatibility
pub fn loadEnvFiles(allocator: std.mem.Allocator, mode: []const u8) !EnvStore {
    var store = EnvStore.init(allocator);
    errdefer store.deinit();

    // Priority order (lowest to highest):
    // 1. .env (base)
    // 2. .env.[MODE]
    // 3. .env.local (highest priority)

    // Load .env (base)
    parseEnvFile(allocator, ".env", &store) catch |err| {
        if (err != error.FileNotFound) return err;
    };

    // Load .env.[MODE]
    var mode_file_buf: [256]u8 = undefined;
    const mode_file = std.fmt.bufPrint(&mode_file_buf, ".env.{s}", .{mode}) catch return error.InvalidFormat;
    parseEnvFile(allocator, mode_file, &store) catch |err| {
        if (err != error.FileNotFound) return err;
    };

    // Load .env.local (highest priority)
    parseEnvFile(allocator, ".env.local", &store) catch |err| {
        if (err != error.FileNotFound) return err;
    };

    return store;
}

// Tests
test "parse simple env content" {
    const allocator = std.testing.allocator;
    var store = EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\# Comment
        \\KEY1=value1
        \\KEY2=value2
        \\
    ;

    try parseEnvContent(allocator, content, ".env", &store);

    try std.testing.expectEqual(@as(usize, 2), store.count());
    try std.testing.expectEqualStrings("value1", store.get("KEY1").?.value);
    try std.testing.expectEqualStrings("value2", store.get("KEY2").?.value);
}

test "parse quoted values" {
    const allocator = std.testing.allocator;
    var store = EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\KEY1="quoted value"
        \\KEY2='single quoted'
        \\KEY3=unquoted
        \\
    ;

    try parseEnvContent(allocator, content, ".env", &store);

    try std.testing.expectEqualStrings("quoted value", store.get("KEY1").?.value);
    try std.testing.expectEqualStrings("single quoted", store.get("KEY2").?.value);
    try std.testing.expectEqualStrings("unquoted", store.get("KEY3").?.value);
}

test "override priority" {
    const allocator = std.testing.allocator;
    var store = EnvStore.init(allocator);
    defer store.deinit();

    // Simulate loading .env first
    const base_content = "KEY1=base_value\n";
    try parseEnvContent(allocator, base_content, ".env", &store);

    // Then .env.local overrides
    const local_content = "KEY1=local_value\n";
    try parseEnvContent(allocator, local_content, ".env.local", &store);

    try std.testing.expectEqualStrings("local_value", store.get("KEY1").?.value);
    try std.testing.expectEqualStrings(".env.local", store.get("KEY1").?.source_file);
}

test "skip empty lines and comments" {
    const allocator = std.testing.allocator;
    var store = EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\
        \\# This is a comment
        \\  # Indented comment
        \\KEY1=value1
        \\
        \\KEY2=value2
        \\
    ;

    try parseEnvContent(allocator, content, ".env", &store);

    try std.testing.expectEqual(@as(usize, 2), store.count());
}

test "handle spaces around equals" {
    const allocator = std.testing.allocator;
    var store = EnvStore.init(allocator);
    defer store.deinit();

    const content =
        \\KEY1 = value1
        \\KEY2=  value2
        \\  KEY3  =value3
        \\
    ;

    try parseEnvContent(allocator, content, ".env", &store);

    try std.testing.expectEqualStrings("value1", store.get("KEY1").?.value);
    try std.testing.expectEqualStrings("value2", store.get("KEY2").?.value);
    try std.testing.expectEqualStrings("value3", store.get("KEY3").?.value);
}

test "multi env store - multiple files same key" {
    const allocator = std.testing.allocator;
    var store = MultiEnvStore.init(allocator);
    defer store.deinit();

    // Simulate loading from multiple files
    const content1 = "API_KEY=dev_key\nDB_URL=localhost\n";
    try parseEnvContentMulti(content1, ".env", &store);

    const content2 = "API_KEY=prod_key\n";
    try parseEnvContentMulti(content2, ".env.production", &store);

    // API_KEY should have 2 values
    const api_entry = store.get("API_KEY").?;
    try std.testing.expectEqual(@as(usize, 2), api_entry.values.items.len);
    try std.testing.expectEqualStrings("dev_key", api_entry.values.items[0].value);
    try std.testing.expectEqualStrings(".env", api_entry.values.items[0].source_file);
    try std.testing.expectEqualStrings("prod_key", api_entry.values.items[1].value);
    try std.testing.expectEqualStrings(".env.production", api_entry.values.items[1].source_file);

    // DB_URL should have 1 value
    const db_entry = store.get("DB_URL").?;
    try std.testing.expectEqual(@as(usize, 1), db_entry.values.items.len);
}

test "multi env store - file tracking" {
    const allocator = std.testing.allocator;
    var store = MultiEnvStore.init(allocator);
    defer store.deinit();

    try store.addFile(".env");
    try store.addFile(".env.production");

    try std.testing.expectEqual(@as(usize, 2), store.files.items.len);
    try std.testing.expectEqualStrings(".env", store.files.items[0]);
    try std.testing.expectEqualStrings(".env.production", store.files.items[1]);
}
