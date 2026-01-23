const std = @import("std");
const env_parser = @import("env-parser.zig");
const masking = @import("masking.zig");
const output = @import("output.zig");

pub const version = "0.2.0";

pub const ExitCode = struct {
    pub const success: u8 = 0;
    pub const general_error: u8 = 1;
    pub const not_found: u8 = 2;
};

pub const Command = enum {
    get,
    set,
    list,
    help,
    version_cmd,
};

pub const Options = struct {
    command: Command = .help,
    key: ?[]const u8 = null,
    value: ?[]const u8 = null,
    unmask_keys: std.ArrayListUnmanaged([]const u8),
    json_format: bool = false,
    quiet: bool = false,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Options {
        return .{
            .unmask_keys = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Options) void {
        self.unmask_keys.deinit(self.allocator);
    }
};

fn printErr(comptime fmt: []const u8, args: anytype) void {
    var buf: [1024]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
    std.fs.File.stderr().writeAll(msg) catch {};
}

fn printOut(comptime fmt: []const u8, args: anytype) void {
    var buf: [4096]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
    std.fs.File.stdout().writeAll(msg) catch {};
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

    if (test_args) |args| {
        // Use provided test arguments
        try arg_list.appendSlice(allocator, args);
    } else {
        // Use process arguments
        var args = try std.process.argsWithAllocator(allocator);
        defer args.deinit();

        // Skip program name
        _ = args.next();

        while (args.next()) |arg| {
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
            } else {
                return error.UnknownFlag;
            }
        } else {
            // Parse command
            if (std.mem.eql(u8, arg, "get")) {
                opts.command = .get;
                // Look ahead for optional key argument (non-flag)
                if (i + 1 < arg_list.items.len) {
                    const next_arg = arg_list.items[i + 1];
                    if (!std.mem.startsWith(u8, next_arg, "-")) {
                        opts.key = next_arg;
                        i += 1; // Consume the key argument
                    }
                    // If next arg is a flag, don't consume it - let the loop handle it
                }
            } else if (std.mem.eql(u8, arg, "set")) {
                opts.command = .set;
                // KEY=VALUE argument
                i += 1;
                if (i >= arg_list.items.len) return error.MissingSetArgument;
                const kv = arg_list.items[i];
                if (std.mem.indexOfScalar(u8, kv, '=')) |eq_pos| {
                    opts.key = kv[0..eq_pos];
                    opts.value = kv[eq_pos + 1 ..];
                } else {
                    return error.InvalidSetFormat;
                }
            } else if (std.mem.eql(u8, arg, "list")) {
                opts.command = .list;
            } else if (std.mem.eql(u8, arg, "help")) {
                opts.command = .help;
            } else if (std.mem.eql(u8, arg, "version")) {
                opts.command = .version_cmd;
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
            error.InvalidSetFormat => printErr("Error: set requires KEY=VALUE format\n", .{}),
            error.MissingSetArgument => printErr("Error: set requires KEY=VALUE argument\n", .{}),
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
        .get => return executeGet(allocator, &opts),
        .set => return executeSet(allocator, &opts),
        .list => return executeList(allocator, &opts),
    }
}

fn executeGet(allocator: std.mem.Allocator, opts: *Options) !u8 {
    var store = env_parser.loadAllEnvFiles(allocator) catch |err| {
        printErr("Error loading env files: {}\n", .{err});
        return ExitCode.general_error;
    };
    defer store.deinit();

    const stdout = std.fs.File.stdout();

    if (opts.key) |key| {
        // Get specific key
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

fn executeSet(allocator: std.mem.Allocator, opts: *Options) !u8 {
    const key = opts.key orelse {
        printErr("Error: set command requires a key\n", .{});
        return ExitCode.general_error;
    };
    const value_to_set = opts.value orelse {
        printErr("Error: set command requires a value\n", .{});
        return ExitCode.general_error;
    };

    // Read existing .env.local content
    var existing_content: std.ArrayListUnmanaged(u8) = .{};
    defer existing_content.deinit(allocator);

    const file_result = std.fs.cwd().openFile(".env.local", .{});
    if (file_result) |f| {
        defer f.close();
        const content = f.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
            printErr("Error reading .env.local: {}\n", .{err});
            return ExitCode.general_error;
        };
        defer allocator.free(content);
        try existing_content.appendSlice(allocator, content);
    } else |err| {
        if (err != error.FileNotFound) {
            printErr("Error reading .env.local: {}\n", .{err});
            return ExitCode.general_error;
        }
        // File doesn't exist, that's fine
    }

    // Check if key already exists and update it, or append
    var new_content: std.ArrayListUnmanaged(u8) = .{};
    defer new_content.deinit(allocator);

    var found = false;
    var lines = std.mem.splitScalar(u8, existing_content.items, '\n');
    var first_line = true;

    while (lines.next()) |line| {
        if (!first_line) {
            try new_content.append(allocator, '\n');
        }
        first_line = false;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len > 0 and trimmed[0] != '#') {
            if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq_pos| {
                const line_key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
                if (std.mem.eql(u8, line_key, key)) {
                    // Replace this line
                    try new_content.appendSlice(allocator, key);
                    try new_content.append(allocator, '=');
                    try new_content.appendSlice(allocator, value_to_set);
                    found = true;
                    continue;
                }
            }
        }
        try new_content.appendSlice(allocator, line);
    }

    if (!found) {
        // Append new key
        if (new_content.items.len > 0 and new_content.items[new_content.items.len - 1] != '\n') {
            try new_content.append(allocator, '\n');
        }
        try new_content.appendSlice(allocator, key);
        try new_content.append(allocator, '=');
        try new_content.appendSlice(allocator, value_to_set);
        try new_content.append(allocator, '\n');
    }

    // Write to .env.local
    const out_file = std.fs.cwd().createFile(".env.local", .{}) catch |err| {
        printErr("Error creating .env.local: {}\n", .{err});
        return ExitCode.general_error;
    };
    defer out_file.close();

    out_file.writeAll(new_content.items) catch |err| {
        printErr("Error writing .env.local: {}\n", .{err});
        return ExitCode.general_error;
    };

    printQuiet(opts, "Set {s} in .env.local\n", .{key});
    return ExitCode.success;
}

fn executeList(allocator: std.mem.Allocator, opts: *Options) !u8 {
    _ = opts;
    var store = env_parser.loadAllEnvFiles(allocator) catch |err| {
        printErr("Error loading env files: {}\n", .{err});
        return ExitCode.general_error;
    };
    defer store.deinit();

    const stdout = std.fs.File.stdout();
    output.writeMultiListOutputToFile(stdout, &store) catch |err| {
        printErr("Error writing output: {}\n", .{err});
        return ExitCode.general_error;
    };
    return ExitCode.success;
}

fn printHelp() void {
    std.fs.File.stdout().writeAll(
        \\enever - Secure environment variable management
        \\
        \\Usage: enever <command> [options]
        \\
        \\Commands:
        \\  get [KEY]           Get all variables or a specific key (shows all .env* files)
        \\  set <KEY>=<VAL>     Set a key-value pair in .env.local
        \\  list                List all available keys (no values)
        \\  help                Show this help message
        \\  version             Show version
        \\
        \\Options:
        \\  -u, --unmask <key>  Show raw value of a protected key
        \\  --json              Output in JSON format (default: TOON)
        \\  -q, --quiet         Suppress non-essential output
        \\  -h, --help          Show help
        \\  -v, --version       Show version
        \\
        \\Exit Codes:
        \\  0  Success
        \\  1  General error
        \\  2  Key/variable not found
        \\
        \\Examples:
        \\  enever get                    # Get all env vars from all .env* files
        \\  enever get API_KEY            # Get API_KEY from each file it appears in
        \\  enever get -u API_KEY         # Get API_KEY unmasked
        \\  enever set API_KEY=secret     # Set key in .env.local
        \\  enever list                   # List all keys
        \\
        \\Output Format (TOON):
        \\  API_KEY:
        \\    .env: ****_dev
        \\    .env.production: ****_prod
        \\
    ) catch {};
}

// Tests
test "parse help flag" {
    // Basic sanity - this mainly tests compilation
    _ = printHelp;
}
