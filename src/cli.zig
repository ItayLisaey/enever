const std = @import("std");
const env_parser = @import("env-parser.zig");
const masking = @import("masking.zig");
const output = @import("output.zig");

pub const version = "0.2.1";

fn getStdOut() std.fs.File {
    return std.fs.File.stdout();
}

fn getStdErr() std.fs.File {
    return std.fs.File.stderr();
}

fn getStdIn() std.fs.File {
    return std.fs.File.stdin();
}

pub const ExitCode = struct {
    pub const success: u8 = 0;
    pub const general_error: u8 = 1;
    pub const not_found: u8 = 2;
    pub const key_exists: u8 = 3;
};

pub const Command = enum {
    read,
    write,
    delete,
    diff,
    list,
    help,
    version_cmd,
};

pub const KeyValue = struct {
    key: []const u8,
    value: []const u8,
};

pub const Options = struct {
    command: Command = .help,
    key: ?[]const u8 = null,
    value: ?[]const u8 = null,
    unmask_keys: std.ArrayListUnmanaged([]const u8),
    json_format: bool = false,
    quiet: bool = false,
    allocator: std.mem.Allocator,
    // New fields for read/write/delete/diff
    file_path: ?[]const u8 = null, // --file flag
    force: bool = false, // --force flag
    paths: std.ArrayListUnmanaged([]const u8), // positional paths (for diff)
    key_values: std.ArrayListUnmanaged(KeyValue), // KEY=value pairs (for write)
    keys: std.ArrayListUnmanaged([]const u8), // keys to delete

    pub fn init(allocator: std.mem.Allocator) Options {
        return .{
            .unmask_keys = .{},
            .paths = .{},
            .key_values = .{},
            .keys = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Options) void {
        self.unmask_keys.deinit(self.allocator);
        self.paths.deinit(self.allocator);
        self.key_values.deinit(self.allocator);
        self.keys.deinit(self.allocator);
    }
};

fn printErr(comptime fmt: []const u8, args: anytype) void {
    var buf: [1024]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
    getStdErr().writeAll(msg) catch {};
}

fn printOut(comptime fmt: []const u8, args: anytype) void {
    var buf: [4096]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
    getStdOut().writeAll(msg) catch {};
}

fn printQuiet(opts: *const Options, comptime fmt: []const u8, args: anytype) void {
    if (!opts.quiet) {
        printOut(fmt, args);
    }
}

pub fn parseArgs(allocator: std.mem.Allocator) !Options {
    return parseArgsFromSlice(allocator, null);
}

/// Parse arguments from a slice (for testing) or from process args (if slice is null)
pub fn parseArgsFromSlice(allocator: std.mem.Allocator, test_args: ?[]const []const u8) !Options {
    var opts = Options.init(allocator);
    errdefer opts.deinit();

    // Collect all arguments into a list for indexed access
    var arg_list = std.ArrayListUnmanaged([]const u8){};
    defer arg_list.deinit(allocator);

    // Track if we own the strings (need to free on Windows)
    var process_args: ?std.process.ArgIterator = null;
    defer if (process_args) |*pa| pa.deinit();

    if (test_args) |args| {
        // Use provided test arguments
        try arg_list.appendSlice(allocator, args);
    } else {
        // Use process arguments
        process_args = try std.process.argsWithAllocator(allocator);

        // Skip program name
        _ = process_args.?.next();

        while (process_args.?.next()) |arg| {
            try arg_list.append(allocator, arg);
        }
    }

    var i: usize = 0;
    while (i < arg_list.items.len) {
        const arg = arg_list.items[i];

        if (std.mem.startsWith(u8, arg, "-")) {
            // Parse flags
            if (std.mem.eql(u8, arg, "-u") or std.mem.eql(u8, arg, "--unmask")) {
                i += 1;
                if (i >= arg_list.items.len) return error.MissingUnmaskKey;
                try opts.unmask_keys.append(allocator, arg_list.items[i]);
            } else if (std.mem.eql(u8, arg, "--json")) {
                opts.json_format = true;
            } else if (std.mem.eql(u8, arg, "-q") or std.mem.eql(u8, arg, "--quiet")) {
                opts.quiet = true;
            } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                opts.command = .help;
                return opts;
            } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--version")) {
                opts.command = .version_cmd;
                return opts;
            } else if (std.mem.eql(u8, arg, "--file") or std.mem.eql(u8, arg, "-f")) {
                i += 1;
                if (i >= arg_list.items.len) return error.MissingFileArg;
                opts.file_path = arg_list.items[i];
            } else if (std.mem.eql(u8, arg, "--force")) {
                opts.force = true;
            } else {
                return error.UnknownFlag;
            }
        } else {
            // Parse command
            if (std.mem.eql(u8, arg, "read")) {
                opts.command = .read;
                // Look ahead for optional path or key argument (non-flag)
                if (i + 1 < arg_list.items.len) {
                    const next_arg = arg_list.items[i + 1];
                    if (!std.mem.startsWith(u8, next_arg, "-")) {
                        opts.key = next_arg; // Could be path or key
                        i += 1;
                    }
                }
            } else if (std.mem.eql(u8, arg, "write")) {
                opts.command = .write;
                // KEY=VALUE args are collected in the second pass below
            } else if (std.mem.eql(u8, arg, "delete")) {
                opts.command = .delete;
                // Keys are collected in the second pass below
            } else if (std.mem.eql(u8, arg, "diff")) {
                opts.command = .diff;
                // Paths are collected in the second pass below
            } else if (std.mem.eql(u8, arg, "list")) {
                opts.command = .list;
            } else if (std.mem.eql(u8, arg, "help")) {
                opts.command = .help;
            } else if (std.mem.eql(u8, arg, "version")) {
                opts.command = .version_cmd;
            } else {
                // Positional argument - collect based on command
                switch (opts.command) {
                    .write => {
                        if (std.mem.indexOfScalar(u8, arg, '=')) |eq_pos| {
                            try opts.key_values.append(allocator, .{
                                .key = arg[0..eq_pos],
                                .value = arg[eq_pos + 1 ..],
                            });
                        }
                    },
                    .delete => {
                        try opts.keys.append(allocator, arg);
                    },
                    .diff => {
                        if (opts.paths.items.len < 2) {
                            try opts.paths.append(allocator, arg);
                        }
                    },
                    else => {},
                }
            }
        }
        i += 1;
    }

    return opts;
}

pub fn run(allocator: std.mem.Allocator) !u8 {
    var opts = parseArgs(allocator) catch |err| {
        switch (err) {
            error.MissingUnmaskKey => printErr("Error: --unmask requires a key\n", .{}),
            error.UnknownFlag => printErr("Error: Unknown flag\n", .{}),
            error.MissingFileArg => printErr("Error: --file requires a path\n", .{}),
            else => printErr("Error: {}\n", .{err}),
        }
        return ExitCode.general_error;
    };
    defer opts.deinit();

    switch (opts.command) {
        .help => {
            printHelp();
            return ExitCode.success;
        },
        .version_cmd => {
            printOut("enever {s}\n", .{version});
            return ExitCode.success;
        },
        .read => return executeRead(allocator, &opts),
        .write => return executeWrite(allocator, &opts),
        .delete => return executeDelete(allocator, &opts),
        .diff => return executeDiff(allocator, &opts),
        .list => return executeList(allocator, &opts),
    }
}

fn executeRead(allocator: std.mem.Allocator, opts: *Options) !u8 {
    // Determine what to read: path to file/directory, or key name
    const target = opts.key; // Could be path or key

    // Check if target is a path (file or directory)
    var store: env_parser.MultiEnvStore = undefined;
    var is_key_lookup = false;

    if (target) |t| {
        // Check if it's a file path
        if (std.mem.endsWith(u8, t, ".env") or std.mem.indexOf(u8, t, "/") != null or std.mem.indexOf(u8, t, ".env.") != null) {
            // It's a path - load from that location
            store = env_parser.loadEnvFilesFromPath(allocator, t) catch |err| {
                printErr("Error loading env files from {s}: {}\n", .{ t, err });
                return ExitCode.general_error;
            };
        } else {
            // It's a key name - load from current directory and look up key
            store = env_parser.loadAllEnvFiles(allocator) catch |err| {
                printErr("Error loading env files: {}\n", .{err});
                return ExitCode.general_error;
            };
            is_key_lookup = true;
        }
    } else {
        // No argument - load from current directory
        store = env_parser.loadAllEnvFiles(allocator) catch |err| {
            printErr("Error loading env files: {}\n", .{err});
            return ExitCode.general_error;
        };
    }
    defer store.deinit();

    const stdout = getStdOut();

    if (is_key_lookup) {
        // Get specific key
        const key = target.?;
        if (store.get(key)) |entry| {
            const should_unmask = for (opts.unmask_keys.items) |uk| {
                if (std.mem.eql(u8, uk, key)) break true;
            } else false;

            if (opts.json_format) {
                output.writeMultiJsonSingleKeyToFile(stdout, entry, should_unmask) catch |err| {
                    printErr("Error writing output: {}\n", .{err});
                    return ExitCode.general_error;
                };
            } else {
                output.writeMultiToonSingleKeyToFile(stdout, entry, should_unmask) catch |err| {
                    printErr("Error writing output: {}\n", .{err});
                    return ExitCode.general_error;
                };
            }
            return ExitCode.success;
        } else {
            if (!opts.quiet) {
                printErr("Key not found: {s}\n", .{key});
            }
            return ExitCode.not_found;
        }
    } else {
        // Get all
        if (opts.json_format) {
            output.writeMultiJsonOutputToFile(stdout, &store, opts.unmask_keys.items) catch |err| {
                printErr("Error writing output: {}\n", .{err});
                return ExitCode.general_error;
            };
        } else {
            output.writeMultiToonOutputToFile(stdout, &store, opts.unmask_keys.items) catch |err| {
                printErr("Error writing output: {}\n", .{err});
                return ExitCode.general_error;
            };
        }
        return ExitCode.success;
    }
}

fn executeWrite(allocator: std.mem.Allocator, opts: *Options) !u8 {
    // Determine target file (default: .env.local)
    const target_file = opts.file_path orelse ".env.local";

    // Check if we have KEY=VALUE args or need to read from stdin
    var key_values_to_write: std.ArrayListUnmanaged(KeyValue) = .{};
    defer key_values_to_write.deinit(allocator);

    if (opts.key_values.items.len > 0) {
        // Use provided KEY=VALUE args
        try key_values_to_write.appendSlice(allocator, opts.key_values.items);
    } else {
        // Read from stdin
        const stdin = getStdIn();
        const stdin_content = stdin.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
            printErr("Error reading from stdin: {}\n", .{err});
            return ExitCode.general_error;
        };
        defer allocator.free(stdin_content);

        // Parse stdin content as KEY=VALUE lines
        var lines = std.mem.splitScalar(u8, stdin_content, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;
            if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq_pos| {
                try key_values_to_write.append(allocator, .{
                    .key = trimmed[0..eq_pos],
                    .value = trimmed[eq_pos + 1 ..],
                });
            }
        }
    }

    if (key_values_to_write.items.len == 0) {
        printErr("Error: write command requires KEY=VALUE arguments or stdin input\n", .{});
        return ExitCode.general_error;
    }

    // Read existing file content
    var existing_content: std.ArrayListUnmanaged(u8) = .{};
    defer existing_content.deinit(allocator);

    const file_result = std.fs.cwd().openFile(target_file, .{});
    if (file_result) |f| {
        defer f.close();
        const content = f.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
            printErr("Error reading {s}: {}\n", .{ target_file, err });
            return ExitCode.general_error;
        };
        defer allocator.free(content);
        try existing_content.appendSlice(allocator, content);
    } else |err| {
        if (err != error.FileNotFound) {
            printErr("Error reading {s}: {}\n", .{ target_file, err });
            return ExitCode.general_error;
        }
        // File doesn't exist, that's fine - we'll create it
    }

    // Check for existing keys (if not --force)
    if (!opts.force) {
        var existing_keys: std.ArrayListUnmanaged([]const u8) = .{};
        defer existing_keys.deinit(allocator);

        for (key_values_to_write.items) |kv| {
            // Check if key exists in file
            var lines = std.mem.splitScalar(u8, existing_content.items, '\n');
            while (lines.next()) |line| {
                const trimmed = std.mem.trim(u8, line, " \t\r");
                if (trimmed.len == 0 or trimmed[0] == '#') continue;
                if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq_pos| {
                    const line_key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
                    if (std.mem.eql(u8, line_key, kv.key)) {
                        try existing_keys.append(allocator, kv.key);
                        break;
                    }
                }
            }
        }

        if (existing_keys.items.len > 0) {
            printErr("Warning: Key(s) already exist in {s}: ", .{target_file});
            for (existing_keys.items, 0..) |k, i| {
                if (i > 0) printErr(", ", .{});
                printErr("{s}", .{k});
            }
            printErr("\nUse --force to overwrite.\n", .{});
            return ExitCode.key_exists;
        }
    }

    // Build new content
    var new_content: std.ArrayListUnmanaged(u8) = .{};
    defer new_content.deinit(allocator);

    // Track which keys we've updated
    var updated_keys = std.StringHashMap(bool).init(allocator);
    defer updated_keys.deinit();

    var lines = std.mem.splitScalar(u8, existing_content.items, '\n');
    var first_line = true;

    while (lines.next()) |line| {
        if (!first_line) {
            try new_content.append(allocator, '\n');
        }
        first_line = false;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        var replaced = false;

        if (trimmed.len > 0 and trimmed[0] != '#') {
            if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq_pos| {
                const line_key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
                // Check if we're updating this key
                for (key_values_to_write.items) |kv| {
                    if (std.mem.eql(u8, line_key, kv.key)) {
                        try new_content.appendSlice(allocator, kv.key);
                        try new_content.append(allocator, '=');
                        try new_content.appendSlice(allocator, kv.value);
                        try updated_keys.put(kv.key, true);
                        replaced = true;
                        break;
                    }
                }
            }
        }
        if (!replaced) {
            try new_content.appendSlice(allocator, line);
        }
    }

    // Append new keys that weren't updated
    for (key_values_to_write.items) |kv| {
        if (!updated_keys.contains(kv.key)) {
            if (new_content.items.len > 0 and new_content.items[new_content.items.len - 1] != '\n') {
                try new_content.append(allocator, '\n');
            }
            try new_content.appendSlice(allocator, kv.key);
            try new_content.append(allocator, '=');
            try new_content.appendSlice(allocator, kv.value);
            try new_content.append(allocator, '\n');
        }
    }

    // Write to file
    const out_file = std.fs.cwd().createFile(target_file, .{}) catch |err| {
        printErr("Error creating {s}: {}\n", .{ target_file, err });
        return ExitCode.general_error;
    };
    defer out_file.close();

    out_file.writeAll(new_content.items) catch |err| {
        printErr("Error writing {s}: {}\n", .{ target_file, err });
        return ExitCode.general_error;
    };

    if (!opts.quiet) {
        for (key_values_to_write.items) |kv| {
            printOut("Set {s} in {s}\n", .{ kv.key, target_file });
        }
    }
    return ExitCode.success;
}

fn executeList(allocator: std.mem.Allocator, opts: *Options) !u8 {
    _ = opts;
    var store = env_parser.loadAllEnvFiles(allocator) catch |err| {
        printErr("Error loading env files: {}\n", .{err});
        return ExitCode.general_error;
    };
    defer store.deinit();

    const stdout = getStdOut();
    output.writeMultiListOutputToFile(stdout, &store) catch |err| {
        printErr("Error writing output: {}\n", .{err});
        return ExitCode.general_error;
    };
    return ExitCode.success;
}

fn executeDelete(allocator: std.mem.Allocator, opts: *Options) !u8 {
    if (opts.keys.items.len == 0) {
        printErr("Error: delete command requires at least one key\n", .{});
        return ExitCode.general_error;
    }

    // Determine target file (default: .env.local)
    const target_file = opts.file_path orelse ".env.local";

    // Read existing file content
    const file = std.fs.cwd().openFile(target_file, .{}) catch |err| {
        if (err == error.FileNotFound) {
            printErr("Error: File not found: {s}\n", .{target_file});
            return ExitCode.general_error;
        }
        printErr("Error reading {s}: {}\n", .{ target_file, err });
        return ExitCode.general_error;
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
        printErr("Error reading {s}: {}\n", .{ target_file, err });
        return ExitCode.general_error;
    };
    defer allocator.free(content);

    // Build new content without the deleted keys
    var new_content: std.ArrayListUnmanaged(u8) = .{};
    defer new_content.deinit(allocator);

    var deleted_keys: std.ArrayListUnmanaged([]const u8) = .{};
    defer deleted_keys.deinit(allocator);

    var lines = std.mem.splitScalar(u8, content, '\n');
    var first_line = true;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        var should_delete = false;

        if (trimmed.len > 0 and trimmed[0] != '#') {
            if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq_pos| {
                const line_key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
                for (opts.keys.items) |key| {
                    if (std.mem.eql(u8, line_key, key)) {
                        should_delete = true;
                        try deleted_keys.append(allocator, key);
                        break;
                    }
                }
            }
        }

        if (!should_delete) {
            if (!first_line) {
                try new_content.append(allocator, '\n');
            }
            first_line = false;
            try new_content.appendSlice(allocator, line);
        }
    }

    // Warn about keys not found
    for (opts.keys.items) |key| {
        var found = false;
        for (deleted_keys.items) |dk| {
            if (std.mem.eql(u8, dk, key)) {
                found = true;
                break;
            }
        }
        if (!found and !opts.quiet) {
            printErr("Warning: Key not found: {s}\n", .{key});
        }
    }

    // Write to file
    const out_file = std.fs.cwd().createFile(target_file, .{}) catch |err| {
        printErr("Error creating {s}: {}\n", .{ target_file, err });
        return ExitCode.general_error;
    };
    defer out_file.close();

    out_file.writeAll(new_content.items) catch |err| {
        printErr("Error writing {s}: {}\n", .{ target_file, err });
        return ExitCode.general_error;
    };

    if (!opts.quiet) {
        for (deleted_keys.items) |key| {
            printOut("Deleted {s} from {s}\n", .{ key, target_file });
        }
    }
    return ExitCode.success;
}

fn executeDiff(allocator: std.mem.Allocator, opts: *Options) !u8 {
    if (opts.paths.items.len < 2) {
        printErr("Error: diff command requires two paths\n", .{});
        return ExitCode.general_error;
    }

    const path1 = opts.paths.items[0];
    const path2 = opts.paths.items[1];

    // Load both env files
    var store1 = env_parser.loadEnvFilesFromPath(allocator, path1) catch |err| {
        printErr("Error loading {s}: {}\n", .{ path1, err });
        return ExitCode.general_error;
    };
    defer store1.deinit();

    var store2 = env_parser.loadEnvFilesFromPath(allocator, path2) catch |err| {
        printErr("Error loading {s}: {}\n", .{ path2, err });
        return ExitCode.general_error;
    };
    defer store2.deinit();

    const stdout = getStdOut();

    // Collect all keys from both stores
    var all_keys = std.StringHashMap(void).init(allocator);
    defer all_keys.deinit();

    var it1 = store1.iterator();
    while (it1.next()) |entry| {
        try all_keys.put(entry.value_ptr.key, {});
    }

    var it2 = store2.iterator();
    while (it2.next()) |entry| {
        try all_keys.put(entry.value_ptr.key, {});
    }

    // Sort keys for consistent output
    var keys: std.ArrayListUnmanaged([]const u8) = .{};
    defer keys.deinit(allocator);

    var key_it = all_keys.keyIterator();
    while (key_it.next()) |key| {
        try keys.append(allocator, key.*);
    }

    std.mem.sort([]const u8, keys.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    // Output differences
    var buf: [4096]u8 = undefined;
    for (keys.items) |key| {
        const in1 = store1.get(key);
        const in2 = store2.get(key);

        if (in1 == null and in2 != null) {
            // Only in second file
            const line = std.fmt.bufPrint(&buf, "+ {s}\n", .{key}) catch continue;
            stdout.writeAll(line) catch {};
        } else if (in1 != null and in2 == null) {
            // Only in first file
            const line = std.fmt.bufPrint(&buf, "- {s}\n", .{key}) catch continue;
            stdout.writeAll(line) catch {};
        } else if (in1 != null and in2 != null) {
            // In both - check if values differ
            const entry1 = in1.?;
            const entry2 = in2.?;

            // Compare first value from each (simplified comparison)
            if (entry1.values.items.len > 0 and entry2.values.items.len > 0) {
                const val1 = entry1.values.items[0].value;
                const val2 = entry2.values.items[0].value;
                if (!std.mem.eql(u8, val1, val2)) {
                    const line = std.fmt.bufPrint(&buf, "~ {s}\n", .{key}) catch continue;
                    stdout.writeAll(line) catch {};
                }
            }
        }
    }

    return ExitCode.success;
}

fn printHelp() void {
    getStdOut().writeAll(
        \\enever - Secure environment variable management
        \\
        \\Usage: enever <command> [options]
        \\
        \\Commands:
        \\  read [path|KEY]     Read env vars (masked by default)
        \\  write KEY=val ...   Write key-value pairs to .env.local
        \\  delete KEY ...      Delete keys from .env.local
        \\  diff <path1> <path2> Compare two .env files
        \\  list                List all available keys (no values)
        \\  help                Show this help message
        \\  version             Show version
        \\
        \\Options:
        \\  -u, --unmask <key>  Show raw value of a key
        \\  -f, --file <path>   Target file for write/delete (default: .env.local)
        \\  --force             Overwrite existing keys (write command)
        \\  --json              Output in JSON format
        \\  -q, --quiet         Suppress non-essential output
        \\  -h, --help          Show help
        \\  -v, --version       Show version
        \\
        \\Exit Codes:
        \\  0  Success
        \\  1  General error
        \\  2  Key not found
        \\  3  Key exists (write without --force)
        \\
        \\Examples:
        \\  enever read                   # Read all .env* files (masked)
        \\  enever read API_KEY           # Read specific key
        \\  enever read -u API_KEY        # Read unmasked
        \\  enever read ./other-project   # Read from another directory
        \\  enever write API_KEY=secret   # Write to .env.local
        \\  enever write --file .env.prod KEY=val
        \\  enever delete OLD_KEY         # Delete from .env.local
        \\  enever diff .env .env.prod    # Compare files
        \\  enever list                   # List all keys
        \\
        \\Diff output:
        \\  + KEY  Only in second file
        \\  - KEY  Only in first file
        \\  ~ KEY  Different values
        \\
    ) catch {};
}

// Tests
test "parse help flag" {
    // Basic sanity - this mainly tests compilation
    _ = printHelp;
}
