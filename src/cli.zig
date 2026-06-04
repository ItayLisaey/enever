const std = @import("std");
const env_parser = @import("env-parser.zig");
const masking = @import("masking.zig");
const output = @import("output.zig");

const File = std.Io.File;

pub const version = "0.4.0";

/// The Io implementation for this run. Set once at the top of `run` so the
/// many small print helpers don't each need it threaded through. A CLI is
/// effectively single-Io, so a module-scope handle is the pragmatic choice.
var g_io: std.Io = undefined;

/// The parent environment map for this run, used by `exec` to seed the child
/// process environment. Set at the top of `run`.
var g_environ_map: ?*const std.process.Environ.Map = null;

fn getStdOut() File {
    return File.stdout();
}

fn getStdErr() File {
    return File.stderr();
}

fn getStdIn() File {
    return File.stdin();
}

/// Write raw bytes to a file (stdout/stderr) through a buffered writer.
fn writeBytes(file: File, bytes: []const u8) void {
    var buf: [4096]u8 = undefined;
    var fw = file.writer(g_io, &buf);
    fw.interface.writeAll(bytes) catch return;
    fw.interface.flush() catch {};
}

pub const ExitCode = struct {
    pub const success: u8 = 0;
    pub const general_error: u8 = 1;
    pub const not_found: u8 = 2;
    pub const key_exists: u8 = 3;
    pub const usage_error: u8 = 64; // invalid arguments / usage (sysexits EX_USAGE)
};

pub const Command = enum {
    read,
    write,
    delete,
    diff,
    list,
    copy,
    schema,
    exec,
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
    dry_run: bool = false, // --dry-run flag (preview mutating ops without writing)
    paths: std.ArrayListUnmanaged([]const u8), // positional paths (for diff)
    key_values: std.ArrayListUnmanaged(KeyValue), // KEY=value pairs (for write)
    keys: std.ArrayListUnmanaged([]const u8), // keys to delete
    child_argv: std.ArrayListUnmanaged([]const u8), // command + args to run (for exec)

    pub fn init(allocator: std.mem.Allocator) Options {
        return .{
            .unmask_keys = .empty,
            .paths = .empty,
            .key_values = .empty,
            .keys = .empty,
            .child_argv = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Options) void {
        // Free duplicated strings
        for (self.unmask_keys.items) |s| self.allocator.free(s);
        self.unmask_keys.deinit(self.allocator);

        for (self.paths.items) |s| self.allocator.free(s);
        self.paths.deinit(self.allocator);

        for (self.key_values.items) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value);
        }
        self.key_values.deinit(self.allocator);

        for (self.keys.items) |s| self.allocator.free(s);
        self.keys.deinit(self.allocator);

        for (self.child_argv.items) |s| self.allocator.free(s);
        self.child_argv.deinit(self.allocator);

        if (self.key) |k| self.allocator.free(k);
        if (self.file_path) |fp| self.allocator.free(fp);
    }
};

fn printErr(comptime fmt: []const u8, args: anytype) void {
    var buf: [4096]u8 = undefined;
    var fw = getStdErr().writer(g_io, &buf);
    fw.interface.print(fmt, args) catch return;
    fw.interface.flush() catch {};
}

fn printOut(comptime fmt: []const u8, args: anytype) void {
    var buf: [4096]u8 = undefined;
    var fw = getStdOut().writer(g_io, &buf);
    fw.interface.print(fmt, args) catch return;
    fw.interface.flush() catch {};
}

fn printQuiet(opts: *const Options, comptime fmt: []const u8, args: anytype) void {
    if (!opts.quiet) {
        printOut(fmt, args);
    }
}

/// Emit a structured error envelope to stderr as a single JSON object:
///   {"error":{"code":"...","message":"...","hint":"..."}}
/// `hint` is omitted when null. Errors always go to stderr so a piped --json
/// stream on stdout stays clean and parseable.
fn printJsonError(code: []const u8, message: []const u8, hint: ?[]const u8) void {
    var buf: [2048]u8 = undefined;
    var fw = getStdErr().writer(g_io, &buf);
    const w = &fw.interface;
    w.writeAll("{\"error\":{\"code\":\"") catch return;
    output.writeJsonEscaped(w, code) catch return;
    w.writeAll("\",\"message\":\"") catch return;
    output.writeJsonEscaped(w, message) catch return;
    if (hint) |h| {
        w.writeAll("\",\"hint\":\"") catch return;
        output.writeJsonEscaped(w, h) catch return;
    }
    w.writeAll("\"}}\n") catch return;
    w.flush() catch {};
}

/// Report an error either as a structured JSON envelope (when --json is active)
/// or as a plain `Error: ...` line. Both forms always go to stderr.
fn reportError(opts: *const Options, code: []const u8, message: []const u8, hint: ?[]const u8) void {
    if (opts.json_format) {
        printJsonError(code, message, hint);
    } else {
        printErr("Error: {s}\n", .{message});
        if (hint) |h| printErr("  hint: {s}\n", .{h});
    }
}

/// Like reportError but formats the message with a format string + args.
fn reportErrorFmt(opts: *const Options, code: []const u8, hint: ?[]const u8, comptime fmt: []const u8, args: anytype) void {
    var buf: [1024]u8 = undefined;
    const message = std.fmt.bufPrint(&buf, fmt, args) catch "internal error";
    reportError(opts, code, message, hint);
}

/// Scan the process arguments for `--json` without fully parsing. Used so
/// argument-parse failures can still be reported as structured JSON.
fn rawArgsHaveJson(args: std.process.Args, gpa: std.mem.Allocator) bool {
    var it = args.iterateAllocator(gpa) catch return false;
    defer it.deinit();
    _ = it.next(); // skip program name
    while (it.next()) |a| {
        if (std.mem.eql(u8, a, "--json")) return true;
    }
    return false;
}

pub fn parseArgs(allocator: std.mem.Allocator, args: std.process.Args) !Options {
    return parseArgsFromSlice(allocator, args, null);
}

/// Parse arguments from a slice (for testing) or from process args (if slice is null)
pub fn parseArgsFromSlice(allocator: std.mem.Allocator, args: ?std.process.Args, test_args: ?[]const []const u8) !Options {
    var opts = Options.init(allocator);
    errdefer opts.deinit();

    // Collect all arguments into a list for indexed access. The strings are
    // borrowed (from the iterator's persistent argv on POSIX, or the test
    // slice); everything the parser keeps in `opts` is duped.
    var arg_list = std.ArrayListUnmanaged([]const u8).empty;
    defer arg_list.deinit(allocator);

    var arg_it: ?std.process.Args.Iterator = null;
    defer if (arg_it) |*it| it.deinit();

    if (test_args) |slice| {
        // Use provided test arguments
        try arg_list.appendSlice(allocator, slice);
    } else {
        // Use process arguments
        arg_it = try args.?.iterateAllocator(allocator);

        // Skip program name
        _ = arg_it.?.next();

        while (arg_it.?.next()) |arg| {
            try arg_list.append(allocator, arg);
        }
    }

    // Once true, every remaining token is captured verbatim as the child
    // command argv for `exec` (so the child's own flags aren't parsed by us).
    var capturing_child = false;

    var i: usize = 0;
    while (i < arg_list.items.len) {
        const arg = arg_list.items[i];

        if (capturing_child) {
            try opts.child_argv.append(allocator, try allocator.dupe(u8, arg));
            i += 1;
            continue;
        }

        // `--` ends enever's own flag parsing for exec; the rest is the command.
        if (opts.command == .exec and std.mem.eql(u8, arg, "--")) {
            capturing_child = true;
            i += 1;
            continue;
        }

        if (std.mem.startsWith(u8, arg, "-")) {
            // Parse flags
            if (std.mem.eql(u8, arg, "-u") or std.mem.eql(u8, arg, "--unmask")) {
                i += 1;
                if (i >= arg_list.items.len) return error.MissingUnmaskKey;
                const duped = try allocator.dupe(u8, arg_list.items[i]);
                try opts.unmask_keys.append(allocator, duped);
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
                opts.file_path = try allocator.dupe(u8, arg_list.items[i]);
            } else if (std.mem.eql(u8, arg, "--force") or std.mem.eql(u8, arg, "-y") or std.mem.eql(u8, arg, "--yes")) {
                opts.force = true;
            } else if (std.mem.eql(u8, arg, "--dry-run") or std.mem.eql(u8, arg, "-n")) {
                opts.dry_run = true;
            } else if (std.mem.eql(u8, arg, "--no-color")) {
                // Accepted for agent/CI compatibility. enever never emits color,
                // so this is a documented no-op rather than an error.
            } else {
                return error.UnknownFlag;
            }
        } else {
            // Parse command
            if (opts.command == .exec) {
                // First bare token after `exec` (no `--` given): the child
                // command starts here. Capture this token and everything after.
                capturing_child = true;
                try opts.child_argv.append(allocator, try allocator.dupe(u8, arg));
            } else if (std.mem.eql(u8, arg, "read")) {
                opts.command = .read;
                // Look ahead for optional path or key argument (non-flag)
                if (i + 1 < arg_list.items.len) {
                    const next_arg = arg_list.items[i + 1];
                    if (!std.mem.startsWith(u8, next_arg, "-")) {
                        opts.key = try allocator.dupe(u8, next_arg); // Could be path or key
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
            } else if (std.mem.eql(u8, arg, "copy") or std.mem.eql(u8, arg, "cp")) {
                opts.command = .copy;
                // Positionals collected below: source, dest, then optional key filters
            } else if (std.mem.eql(u8, arg, "list")) {
                opts.command = .list;
            } else if (std.mem.eql(u8, arg, "schema")) {
                opts.command = .schema;
            } else if (std.mem.eql(u8, arg, "exec") or std.mem.eql(u8, arg, "run")) {
                opts.command = .exec;
                // Remaining tokens become the child command (see capture logic).
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
                                .key = try allocator.dupe(u8, arg[0..eq_pos]),
                                .value = try allocator.dupe(u8, arg[eq_pos + 1 ..]),
                            });
                        }
                    },
                    .delete => {
                        const duped = try allocator.dupe(u8, arg);
                        try opts.keys.append(allocator, duped);
                    },
                    .diff => {
                        if (opts.paths.items.len < 2) {
                            const duped = try allocator.dupe(u8, arg);
                            try opts.paths.append(allocator, duped);
                        }
                    },
                    .copy => {
                        // source, dest, then optional KEY filters (all positional)
                        const duped = try allocator.dupe(u8, arg);
                        try opts.paths.append(allocator, duped);
                    },
                    else => {},
                }
            }
        }
        i += 1;
    }

    return opts;
}

pub fn run(io: std.Io, gpa: std.mem.Allocator, args: std.process.Args, environ_map: *const std.process.Environ.Map) !u8 {
    g_io = io;
    g_environ_map = environ_map;

    var opts = parseArgs(gpa, args) catch |err| {
        const json = rawArgsHaveJson(args, gpa);
        const info: struct { code: []const u8, msg: []const u8, hint: ?[]const u8 } = switch (err) {
            error.MissingUnmaskKey => .{ .code = "USAGE", .msg = "--unmask requires a key", .hint = "usage: enever read -u KEY" },
            error.UnknownFlag => .{ .code = "USAGE", .msg = "unknown flag", .hint = "run `enever schema` to list valid flags" },
            error.MissingFileArg => .{ .code = "USAGE", .msg = "--file requires a path", .hint = "usage: enever write -f .env.local KEY=value" },
            else => .{ .code = "USAGE", .msg = "invalid arguments", .hint = "run `enever help` for usage" },
        };
        if (json) {
            printJsonError(info.code, info.msg, info.hint);
        } else {
            printErr("Error: {s}\n", .{info.msg});
            if (info.hint) |h| printErr("  hint: {s}\n", .{h});
        }
        return ExitCode.usage_error;
    };
    defer opts.deinit();

    switch (opts.command) {
        .help => {
            printHelp();
            return ExitCode.success;
        },
        .version_cmd => {
            if (opts.json_format) {
                printOut("{{\"name\":\"enever\",\"version\":\"{s}\"}}\n", .{version});
            } else {
                printOut("enever {s}\n", .{version});
            }
            return ExitCode.success;
        },
        .schema => return executeSchema(),
        .copy => return executeCopy(gpa, &opts),
        .exec => return executeExec(gpa, &opts),
        .read => return executeRead(gpa, &opts),
        .write => return executeWrite(gpa, &opts),
        .delete => return executeDelete(gpa, &opts),
        .diff => return executeDiff(gpa, &opts),
        .list => return executeList(gpa, &opts),
    }
}

fn executeRead(allocator: std.mem.Allocator, opts: *Options) !u8 {
    // Determine what to read: path to file/directory, or key name
    const target = opts.key; // Could be path or key

    // Check if target is a path (file or directory)
    var store: env_parser.MultiEnvStore = undefined;
    var is_key_lookup = false;

    if (target) |t| {
        // First, check if it's an actual file or directory path
        // Try to open as directory first (works cross-platform including Windows)
        const is_path = blk: {
            // Check if path is absolute (handles both Unix and Windows paths)
            const is_absolute = std.fs.path.isAbsolute(t);

            // Try opening as directory
            if (is_absolute) {
                if (std.Io.Dir.openDirAbsolute(g_io, t, .{})) |dir| {
                    var d = dir;
                    d.close(g_io);
                    break :blk true;
                } else |_| {}
            } else {
                if (std.Io.Dir.cwd().openDir(g_io, t, .{})) |dir| {
                    var d = dir;
                    d.close(g_io);
                    break :blk true;
                } else |_| {}
            }

            // Try opening as file
            if (is_absolute) {
                if (std.Io.Dir.openFileAbsolute(g_io, t, .{})) |file| {
                    file.close(g_io);
                    break :blk true;
                } else |_| {}
            } else {
                if (std.Io.Dir.cwd().openFile(g_io, t, .{})) |file| {
                    file.close(g_io);
                    break :blk true;
                } else |_| {}
            }

            // Path doesn't exist - check for path-like patterns (starts with . or contains path separator)
            // Check for both forward slash (Unix) and backslash (Windows)
            break :blk std.mem.startsWith(u8, t, ".") or
                std.mem.indexOfScalar(u8, t, '/') != null or
                std.mem.indexOfScalar(u8, t, '\\') != null;
        };

        if (is_path) {
            // It's a path - load from that location
            store = env_parser.loadEnvFilesFromPath(g_io, allocator, t) catch |err| {
                reportErrorFmt(opts, "LOAD_FAILED", null, "loading env files from {s}: {s}", .{ t, @errorName(err) });
                return ExitCode.general_error;
            };
        } else {
            // It's a key name - load from current directory and look up key
            store = env_parser.loadAllEnvFiles(g_io, allocator) catch |err| {
                reportErrorFmt(opts, "LOAD_FAILED", null, "loading env files: {s}", .{@errorName(err)});
                return ExitCode.general_error;
            };
            is_key_lookup = true;
        }
    } else {
        // No argument - load from current directory
        store = env_parser.loadAllEnvFiles(g_io, allocator) catch |err| {
            reportErrorFmt(opts, "LOAD_FAILED", null, "loading env files: {s}", .{@errorName(err)});
            return ExitCode.general_error;
        };
    }
    defer store.deinit();

    var obuf: [4096]u8 = undefined;
    var fw = getStdOut().writer(g_io, &obuf);
    const w = &fw.interface;

    if (is_key_lookup) {
        // Get specific key
        const key = target.?;
        if (store.get(key)) |entry| {
            const should_unmask = for (opts.unmask_keys.items) |uk| {
                if (std.mem.eql(u8, uk, key)) break true;
            } else false;

            const res = if (opts.json_format)
                output.writeMultiJsonSingleKey(w, entry, should_unmask)
            else
                output.writeMultiToonSingleKey(w, entry, should_unmask);
            res catch |err| {
                reportErrorFmt(opts, "OUTPUT_FAILED", null, "writing output: {s}", .{@errorName(err)});
                return ExitCode.general_error;
            };
            w.flush() catch {};
            return ExitCode.success;
        } else {
            if (!opts.quiet) {
                reportErrorFmt(opts, "KEY_NOT_FOUND", "run `enever list` to see available keys", "key not found: {s}", .{key});
            }
            return ExitCode.not_found;
        }
    } else {
        // Get all
        const res = if (opts.json_format)
            output.writeMultiJsonOutput(w, &store, opts.unmask_keys.items)
        else
            output.writeMultiToonOutput(w, &store, opts.unmask_keys.items);
        res catch |err| {
            reportErrorFmt(opts, "OUTPUT_FAILED", null, "writing output: {s}", .{@errorName(err)});
            return ExitCode.general_error;
        };
        w.flush() catch {};
        return ExitCode.success;
    }
}

fn executeWrite(allocator: std.mem.Allocator, opts: *Options) !u8 {
    // Determine target file (default: .env.local)
    const target_file = opts.file_path orelse ".env.local";

    // Check if we have KEY=VALUE args or need to read from stdin
    var key_values_to_write: std.ArrayListUnmanaged(KeyValue) = .empty;
    defer key_values_to_write.deinit(allocator);

    // When reading from stdin, the parsed key/value slices point into this
    // buffer, so it must outlive all uses of key_values_to_write. Keep it at
    // function scope rather than freeing it inside the stdin branch.
    var stdin_content: ?[]u8 = null;
    defer if (stdin_content) |c| allocator.free(c);

    if (opts.key_values.items.len > 0) {
        // Use provided KEY=VALUE args
        try key_values_to_write.appendSlice(allocator, opts.key_values.items);
    } else {
        // Read from stdin - but first check if stdin is a TTY
        const stdin = getStdIn();
        if (stdin.isTty(g_io) catch false) {
            reportError(opts, "USAGE", "write requires KEY=value arguments", "usage: enever write KEY=value [KEY2=value2 ...]  (or pipe: echo 'KEY=value' | enever write)");
            return ExitCode.usage_error;
        }

        var stdin_buf: [4096]u8 = undefined;
        var stdin_reader = stdin.reader(g_io, &stdin_buf);
        const content = stdin_reader.interface.allocRemaining(allocator, .limited(1024 * 1024)) catch |err| {
            reportErrorFmt(opts, "STDIN_READ_FAILED", null, "reading from stdin: {s}", .{@errorName(err)});
            return ExitCode.general_error;
        };
        stdin_content = content;

        // Parse stdin content as KEY=VALUE lines
        var lines = std.mem.splitScalar(u8, content, '\n');
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
        reportError(opts, "USAGE", "write requires KEY=value arguments or stdin input", "usage: enever write KEY=value");
        return ExitCode.usage_error;
    }

    // Read existing file content
    var existing_content: std.ArrayListUnmanaged(u8) = .empty;
    defer existing_content.deinit(allocator);

    if (std.Io.Dir.cwd().readFileAlloc(g_io, target_file, allocator, .limited(1024 * 1024))) |content| {
        defer allocator.free(content);
        try existing_content.appendSlice(allocator, content);
    } else |err| {
        if (err != error.FileNotFound) {
            reportErrorFmt(opts, "READ_FAILED", null, "reading {s}: {s}", .{ target_file, @errorName(err) });
            return ExitCode.general_error;
        }
        // File doesn't exist, that's fine - we'll create it
    }

    // Check for existing keys (if not --force)
    if (!opts.force) {
        var existing_keys: std.ArrayListUnmanaged([]const u8) = .empty;
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
            if (opts.json_format) {
                var ebuf: [1024]u8 = undefined;
                var efw = getStdErr().writer(g_io, &ebuf);
                const ew = &efw.interface;
                ew.writeAll("{\"error\":{\"code\":\"KEY_EXISTS\",\"message\":\"key(s) already exist in ") catch {};
                output.writeJsonEscaped(ew, target_file) catch {};
                ew.writeAll("\",\"keys\":[") catch {};
                for (existing_keys.items, 0..) |k, i| {
                    if (i > 0) ew.writeAll(",") catch {};
                    ew.writeByte('"') catch {};
                    output.writeJsonEscaped(ew, k) catch {};
                    ew.writeByte('"') catch {};
                }
                ew.writeAll("],\"hint\":\"pass --force to overwrite\"}}\n") catch {};
                ew.flush() catch {};
            } else {
                printErr("Warning: Key(s) already exist in {s}: ", .{target_file});
                for (existing_keys.items, 0..) |k, i| {
                    if (i > 0) printErr(", ", .{});
                    printErr("{s}", .{k});
                }
                printErr("\nUse --force to overwrite.\n", .{});
            }
            return ExitCode.key_exists;
        }
    }

    // Build new content
    var new_content: std.ArrayListUnmanaged(u8) = .empty;
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

    // Write to file (unless this is a dry run)
    if (!opts.dry_run) {
        std.Io.Dir.cwd().writeFile(g_io, .{ .sub_path = target_file, .data = new_content.items }) catch |err| {
            reportErrorFmt(opts, "WRITE_FAILED", null, "writing {s}: {s}", .{ target_file, @errorName(err) });
            return ExitCode.general_error;
        };
    }

    if (opts.json_format) {
        var obuf: [4096]u8 = undefined;
        var fw = getStdOut().writer(g_io, &obuf);
        const w = &fw.interface;
        try w.writeAll("{\"written\":[");
        for (key_values_to_write.items, 0..) |kv, i| {
            if (i > 0) try w.writeAll(",");
            try w.writeAll("{\"key\":\"");
            try output.writeJsonEscaped(w, kv.key);
            try w.writeAll("\"}");
        }
        try w.writeAll("],\"file\":\"");
        try output.writeJsonEscaped(w, target_file);
        try w.print("\",\"dry_run\":{}}}\n", .{opts.dry_run});
        try w.flush();
    } else if (!opts.quiet) {
        const prefix = if (opts.dry_run) "[dry-run] Would set" else "Set";
        for (key_values_to_write.items) |kv| {
            printOut("{s} {s} in {s}\n", .{ prefix, kv.key, target_file });
        }
    }
    return ExitCode.success;
}

fn executeList(allocator: std.mem.Allocator, opts: *Options) !u8 {
    var store = env_parser.loadAllEnvFiles(g_io, allocator) catch |err| {
        reportErrorFmt(opts, "LOAD_FAILED", null, "loading env files: {s}", .{@errorName(err)});
        return ExitCode.general_error;
    };
    defer store.deinit();

    var obuf: [4096]u8 = undefined;
    var fw = getStdOut().writer(g_io, &obuf);
    const w = &fw.interface;
    const write_result = if (opts.json_format)
        output.writeMultiListJson(w, &store)
    else
        output.writeMultiListOutput(w, &store);
    write_result catch |err| {
        reportErrorFmt(opts, "OUTPUT_FAILED", null, "writing output: {s}", .{@errorName(err)});
        return ExitCode.general_error;
    };
    w.flush() catch {};
    return ExitCode.success;
}

fn executeDelete(allocator: std.mem.Allocator, opts: *Options) !u8 {
    if (opts.keys.items.len == 0) {
        reportError(opts, "USAGE", "delete requires at least one key", "usage: enever delete KEY [KEY2 ...]");
        return ExitCode.usage_error;
    }

    // Determine target file (default: .env.local)
    const target_file = opts.file_path orelse ".env.local";

    // Read existing file content
    const content = std.Io.Dir.cwd().readFileAlloc(g_io, target_file, allocator, .limited(1024 * 1024)) catch |err| {
        if (err == error.FileNotFound) {
            reportErrorFmt(opts, "FILE_NOT_FOUND", null, "file not found: {s}", .{target_file});
            return ExitCode.general_error;
        }
        reportErrorFmt(opts, "READ_FAILED", null, "reading {s}: {s}", .{ target_file, @errorName(err) });
        return ExitCode.general_error;
    };
    defer allocator.free(content);

    // Build new content without the deleted keys
    var new_content: std.ArrayListUnmanaged(u8) = .empty;
    defer new_content.deinit(allocator);

    var deleted_keys: std.ArrayListUnmanaged([]const u8) = .empty;
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

    // Collect keys that were requested but not present
    var not_found_keys: std.ArrayListUnmanaged([]const u8) = .empty;
    defer not_found_keys.deinit(allocator);
    for (opts.keys.items) |key| {
        var found = false;
        for (deleted_keys.items) |dk| {
            if (std.mem.eql(u8, dk, key)) {
                found = true;
                break;
            }
        }
        if (!found) {
            try not_found_keys.append(allocator, key);
        }
    }

    // Write to file (unless this is a dry run)
    if (!opts.dry_run) {
        std.Io.Dir.cwd().writeFile(g_io, .{ .sub_path = target_file, .data = new_content.items }) catch |err| {
            reportErrorFmt(opts, "WRITE_FAILED", null, "writing {s}: {s}", .{ target_file, @errorName(err) });
            return ExitCode.general_error;
        };
    }

    if (opts.json_format) {
        var obuf: [4096]u8 = undefined;
        var fw = getStdOut().writer(g_io, &obuf);
        const w = &fw.interface;
        try w.writeAll("{\"deleted\":[");
        for (deleted_keys.items, 0..) |key, i| {
            if (i > 0) try w.writeAll(",");
            try w.writeByte('"');
            try output.writeJsonEscaped(w, key);
            try w.writeByte('"');
        }
        try w.writeAll("],\"not_found\":[");
        for (not_found_keys.items, 0..) |key, i| {
            if (i > 0) try w.writeAll(",");
            try w.writeByte('"');
            try output.writeJsonEscaped(w, key);
            try w.writeByte('"');
        }
        try w.writeAll("],\"file\":\"");
        try output.writeJsonEscaped(w, target_file);
        try w.print("\",\"dry_run\":{}}}\n", .{opts.dry_run});
        try w.flush();
    } else {
        if (!opts.quiet) {
            for (not_found_keys.items) |key| {
                printErr("Warning: Key not found: {s}\n", .{key});
            }
            const prefix = if (opts.dry_run) "[dry-run] Would delete" else "Deleted";
            for (deleted_keys.items) |key| {
                printOut("{s} {s} from {s}\n", .{ prefix, key, target_file });
            }
        }
    }
    return ExitCode.success;
}

fn executeDiff(allocator: std.mem.Allocator, opts: *Options) !u8 {
    if (opts.paths.items.len < 2) {
        reportError(opts, "USAGE", "diff requires two paths", "usage: enever diff <path1> <path2>");
        return ExitCode.usage_error;
    }

    const path1 = opts.paths.items[0];
    const path2 = opts.paths.items[1];

    // Load both env files
    var store1 = env_parser.loadEnvFilesFromPath(g_io, allocator, path1) catch |err| {
        reportErrorFmt(opts, "LOAD_FAILED", null, "loading {s}: {s}", .{ path1, @errorName(err) });
        return ExitCode.general_error;
    };
    defer store1.deinit();

    var store2 = env_parser.loadEnvFilesFromPath(g_io, allocator, path2) catch |err| {
        reportErrorFmt(opts, "LOAD_FAILED", null, "loading {s}: {s}", .{ path2, @errorName(err) });
        return ExitCode.general_error;
    };
    defer store2.deinit();

    var obuf: [4096]u8 = undefined;
    var fw = getStdOut().writer(g_io, &obuf);
    const w = &fw.interface;

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
    var keys: std.ArrayListUnmanaged([]const u8) = .empty;
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

    // Classify each key. status: "added" (only in path2), "removed" (only in
    // path1), "changed" (present in both but value differs). Unchanged keys are
    // omitted from output in both formats.
    const Status = enum { added, removed, changed, unchanged };
    const classify = struct {
        fn f(s1: *env_parser.MultiEnvStore, s2: *env_parser.MultiEnvStore, key: []const u8) Status {
            const in1 = s1.get(key);
            const in2 = s2.get(key);
            if (in1 == null and in2 != null) return .added;
            if (in1 != null and in2 == null) return .removed;
            if (in1) |e1| if (in2) |e2| {
                if (e1.values.items.len > 0 and e2.values.items.len > 0) {
                    if (!std.mem.eql(u8, e1.values.items[0].value, e2.values.items[0].value)) {
                        return .changed;
                    }
                }
            };
            return .unchanged;
        }
    }.f;

    if (opts.json_format) {
        try w.writeAll("{\"diff\":[");
        var first = true;
        for (keys.items) |key| {
            const status = classify(&store1, &store2, key);
            if (status == .unchanged) continue;
            const status_str = switch (status) {
                .added => "added",
                .removed => "removed",
                .changed => "changed",
                .unchanged => unreachable,
            };
            if (!first) try w.writeAll(",");
            first = false;
            try w.writeAll("{\"key\":\"");
            try output.writeJsonEscaped(w, key);
            try w.print("\",\"status\":\"{s}\"}}", .{status_str});
        }
        try w.writeAll("]}\n");
    } else {
        for (keys.items) |key| {
            const sym: ?[]const u8 = switch (classify(&store1, &store2, key)) {
                .added => "+",
                .removed => "-",
                .changed => "~",
                .unchanged => null,
            };
            if (sym) |s| {
                w.print("{s} {s}\n", .{ s, key }) catch continue;
            }
        }
    }
    w.flush() catch {};

    return ExitCode.success;
}

/// Whether an env file body already assigns `key` (ignoring comments/blanks).
fn keyExistsInContent(content: []const u8, key: []const u8) bool {
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq| {
            const line_key = std.mem.trim(u8, trimmed[0..eq], " \t");
            if (std.mem.eql(u8, line_key, key)) return true;
        }
    }
    return false;
}

/// Copy env vars from a source (file or directory) into a destination .env
/// file. Real values are copied but never printed. Existing destination keys
/// are preserved unless `--force` is given (they are reported as "skipped").
/// An optional list of keys restricts what is copied.
fn executeCopy(allocator: std.mem.Allocator, opts: *Options) !u8 {
    if (opts.paths.items.len < 2) {
        reportError(opts, "USAGE", "copy requires a source and a destination", "usage: enever copy <source> <dest> [KEY ...]");
        return ExitCode.usage_error;
    }
    const src = opts.paths.items[0];
    const dst = opts.paths.items[1];
    const key_filter = opts.paths.items[2..];

    // Load the source and resolve each key to its highest-precedence value.
    var store = env_parser.loadEnvFilesFromPath(g_io, allocator, src) catch |err| {
        reportErrorFmt(opts, "LOAD_FAILED", null, "loading {s}: {s}", .{ src, @errorName(err) });
        return ExitCode.general_error;
    };
    defer store.deinit();

    // Filter keys present in the source vs requested (for not_found reporting).
    var not_found: std.ArrayListUnmanaged([]const u8) = .empty;
    defer not_found.deinit(allocator);
    for (key_filter) |k| {
        if (store.get(k) == null) try not_found.append(allocator, k);
    }

    // Collect the (key, resolved value) pairs to copy, sorted for determinism.
    var pairs: std.ArrayListUnmanaged(KeyValue) = .empty;
    defer pairs.deinit(allocator);
    {
        var it = store.iterator();
        while (it.next()) |entry| {
            const key = entry.value_ptr.key;
            if (key_filter.len > 0) {
                const wanted = for (key_filter) |k| {
                    if (std.mem.eql(u8, k, key)) break true;
                } else false;
                if (!wanted) continue;
            }
            const values = entry.value_ptr.values.items;
            if (values.len == 0) continue;
            var best = values[0];
            var best_rank = envFilePrecedence(values[0].source_file);
            for (values[1..]) |fv| {
                const r = envFilePrecedence(fv.source_file);
                if (r >= best_rank) {
                    best = fv;
                    best_rank = r;
                }
            }
            try pairs.append(allocator, .{ .key = key, .value = best.value });
        }
    }
    std.mem.sort(KeyValue, pairs.items, {}, struct {
        fn lt(_: void, a: KeyValue, b: KeyValue) bool {
            return std.mem.lessThan(u8, a.key, b.key);
        }
    }.lt);

    // Read existing destination content (a missing file is fine).
    var existing: std.ArrayListUnmanaged(u8) = .empty;
    defer existing.deinit(allocator);
    if (std.Io.Dir.cwd().readFileAlloc(g_io, dst, allocator, .limited(1024 * 1024))) |content| {
        defer allocator.free(content);
        try existing.appendSlice(allocator, content);
    } else |err| {
        if (err != error.FileNotFound) {
            reportErrorFmt(opts, "READ_FAILED", null, "reading {s}: {s}", .{ dst, @errorName(err) });
            return ExitCode.general_error;
        }
    }

    // Split into keys to write (new, or overwritten with --force) vs skipped.
    var to_write: std.ArrayListUnmanaged(KeyValue) = .empty;
    defer to_write.deinit(allocator);
    var skipped: std.ArrayListUnmanaged([]const u8) = .empty;
    defer skipped.deinit(allocator);
    for (pairs.items) |kv| {
        if (keyExistsInContent(existing.items, kv.key) and !opts.force) {
            try skipped.append(allocator, kv.key);
        } else {
            try to_write.append(allocator, kv);
        }
    }

    // Merge: replace updated keys in place, append the rest.
    var new_content: std.ArrayListUnmanaged(u8) = .empty;
    defer new_content.deinit(allocator);
    var updated = std.StringHashMap(bool).init(allocator);
    defer updated.deinit();

    var lines = std.mem.splitScalar(u8, existing.items, '\n');
    var first_line = true;
    while (lines.next()) |line| {
        if (!first_line) try new_content.append(allocator, '\n');
        first_line = false;
        const trimmed = std.mem.trim(u8, line, " \t\r");
        var replaced = false;
        if (trimmed.len > 0 and trimmed[0] != '#') {
            if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq| {
                const line_key = std.mem.trim(u8, trimmed[0..eq], " \t");
                for (to_write.items) |kv| {
                    if (std.mem.eql(u8, line_key, kv.key)) {
                        try new_content.appendSlice(allocator, kv.key);
                        try new_content.append(allocator, '=');
                        try new_content.appendSlice(allocator, kv.value);
                        try updated.put(kv.key, true);
                        replaced = true;
                        break;
                    }
                }
            }
        }
        if (!replaced) try new_content.appendSlice(allocator, line);
    }
    for (to_write.items) |kv| {
        if (!updated.contains(kv.key)) {
            if (new_content.items.len > 0 and new_content.items[new_content.items.len - 1] != '\n') {
                try new_content.append(allocator, '\n');
            }
            try new_content.appendSlice(allocator, kv.key);
            try new_content.append(allocator, '=');
            try new_content.appendSlice(allocator, kv.value);
            try new_content.append(allocator, '\n');
        }
    }

    if (!opts.dry_run) {
        std.Io.Dir.cwd().writeFile(g_io, .{ .sub_path = dst, .data = new_content.items }) catch |err| {
            reportErrorFmt(opts, "WRITE_FAILED", null, "writing {s}: {s}", .{ dst, @errorName(err) });
            return ExitCode.general_error;
        };
    }

    if (opts.json_format) {
        var obuf: [4096]u8 = undefined;
        var fw = getStdOut().writer(g_io, &obuf);
        const w = &fw.interface;
        try w.writeAll("{\"copied\":[");
        for (to_write.items, 0..) |kv, i| {
            if (i > 0) try w.writeAll(",");
            try w.writeByte('"');
            try output.writeJsonEscaped(w, kv.key);
            try w.writeByte('"');
        }
        try w.writeAll("],\"skipped\":[");
        for (skipped.items, 0..) |k, i| {
            if (i > 0) try w.writeAll(",");
            try w.writeByte('"');
            try output.writeJsonEscaped(w, k);
            try w.writeByte('"');
        }
        try w.writeAll("],\"not_found\":[");
        for (not_found.items, 0..) |k, i| {
            if (i > 0) try w.writeAll(",");
            try w.writeByte('"');
            try output.writeJsonEscaped(w, k);
            try w.writeByte('"');
        }
        try w.writeAll("],\"from\":\"");
        try output.writeJsonEscaped(w, src);
        try w.writeAll("\",\"to\":\"");
        try output.writeJsonEscaped(w, dst);
        try w.print("\",\"dry_run\":{}}}\n", .{opts.dry_run});
        try w.flush();
    } else if (!opts.quiet) {
        const prefix = if (opts.dry_run) "[dry-run] Would copy" else "Copied";
        for (to_write.items) |kv| printOut("{s} {s} -> {s}\n", .{ prefix, kv.key, dst });
        for (skipped.items) |k| printErr("Skipped {s} (already in {s}; use --force)\n", .{ k, dst });
        for (not_found.items) |k| printErr("Warning: key not found in {s}: {s}\n", .{ src, k });
    }
    return ExitCode.success;
}

/// Precedence rank for an env filename when resolving a single value per key.
/// Higher wins. Mirrors common tooling: `.env` < `.env.<mode>` < `.env.local`
/// < `.env.<mode>.local`. A leading `+` (used by some fixtures) is ignored.
fn envFilePrecedence(name: []const u8) u8 {
    var n = name;
    if (n.len > 0 and n[0] == '+') n = n[1..];
    var rank: u8 = 0;
    var base = n;
    if (std.mem.endsWith(u8, n, ".local")) {
        rank += 2;
        base = n[0 .. n.len - ".local".len];
    }
    if (!std.mem.eql(u8, base, ".env")) rank += 1;
    return rank;
}

/// Run a command with the resolved (real, unmasked) env vars injected into its
/// environment. The values are passed to the child process only — they are
/// never printed to stdout/stderr, so secrets stay out of terminals and agent
/// context. The child's stdio is inherited and its exit code is propagated.
fn executeExec(allocator: std.mem.Allocator, opts: *Options) !u8 {
    if (opts.child_argv.items.len == 0) {
        reportError(opts, "USAGE", "exec requires a command to run", "usage: enever exec -- <command> [args...]");
        return ExitCode.usage_error;
    }

    // Load real values from the target path, or via discovery in the cwd.
    var store = if (opts.file_path) |fp|
        env_parser.loadEnvFilesFromPath(g_io, allocator, fp) catch |err| {
            reportErrorFmt(opts, "LOAD_FAILED", null, "loading env files: {s}", .{@errorName(err)});
            return ExitCode.general_error;
        }
    else
        env_parser.loadAllEnvFiles(g_io, allocator) catch |err| {
            reportErrorFmt(opts, "LOAD_FAILED", null, "loading env files: {s}", .{@errorName(err)});
            return ExitCode.general_error;
        };
    defer store.deinit();

    // Inherit the parent environment, then overlay resolved values (the
    // highest-precedence file wins for each key).
    var env_map = (g_environ_map orelse return ExitCode.general_error).clone(allocator) catch |err| {
        reportErrorFmt(opts, "EXEC_FAILED", null, "reading environment: {s}", .{@errorName(err)});
        return ExitCode.general_error;
    };
    defer env_map.deinit();

    var loaded_count: usize = 0;
    var it = store.iterator();
    while (it.next()) |entry| {
        const values = entry.value_ptr.values.items;
        if (values.len == 0) continue;
        var best = values[0];
        var best_rank = envFilePrecedence(values[0].source_file);
        for (values[1..]) |fv| {
            const r = envFilePrecedence(fv.source_file);
            if (r >= best_rank) {
                best = fv;
                best_rank = r;
            }
        }
        env_map.put(entry.value_ptr.key, best.value) catch |err| {
            reportErrorFmt(opts, "EXEC_FAILED", null, "setting environment: {s}", .{@errorName(err)});
            return ExitCode.general_error;
        };
        loaded_count += 1;
    }

    if (!opts.quiet) {
        // Count and command name only — never the values themselves.
        printErr("enever: injected {d} variable(s) into `{s}`\n", .{ loaded_count, opts.child_argv.items[0] });
    }

    // Spawn with inherited stdio so the child's output passes straight through;
    // the injected secrets never appear in enever's own output.
    var child = std.process.spawn(g_io, .{
        .argv = opts.child_argv.items,
        .environ_map = &env_map,
    }) catch |err| {
        switch (err) {
            error.FileNotFound => {
                reportErrorFmt(opts, "COMMAND_NOT_FOUND", "is the command installed and on PATH?", "command not found: {s}", .{opts.child_argv.items[0]});
                return 127; // POSIX convention: command not found
            },
            error.AccessDenied => {
                reportErrorFmt(opts, "COMMAND_NOT_EXECUTABLE", null, "permission denied: {s}", .{opts.child_argv.items[0]});
                return 126; // POSIX convention: not executable
            },
            else => {
                reportErrorFmt(opts, "EXEC_FAILED", null, "failed to run {s}: {s}", .{ opts.child_argv.items[0], @errorName(err) });
                return ExitCode.general_error;
            },
        }
    };

    const term = child.wait(g_io) catch |err| {
        reportErrorFmt(opts, "EXEC_FAILED", null, "waiting for {s}: {s}", .{ opts.child_argv.items[0], @errorName(err) });
        return ExitCode.general_error;
    };

    return switch (term) {
        .exited => |code| code,
        .signal => |sig| @intCast(128 + (@as(u32, @intCast(@intFromEnum(sig))) & 0x7f)),
        .stopped, .unknown => ExitCode.general_error,
    };
}

/// Emit a stable, machine-readable description of the entire CLI surface as a
/// single JSON object. This is the primary affordance for agents: one call
/// reveals every command, flag, and exit code without guessing.
fn executeSchema() !u8 {
    const prefix =
        \\{
        \\  "name": "enever",
        \\  "version": "
    ;
    const suffix =
        \\",
        \\  "description": "Secure environment variable management. Values are masked by default.",
        \\  "global_flags": [
        \\    {"name": "--json", "type": "boolean", "description": "Emit machine-readable JSON on stdout; structured errors on stderr"},
        \\    {"name": "--quiet", "alias": "-q", "type": "boolean", "description": "Suppress non-essential output"},
        \\    {"name": "--no-color", "type": "boolean", "description": "Disable color (no-op; enever never emits color)"},
        \\    {"name": "--help", "alias": "-h", "type": "boolean", "description": "Show help"},
        \\    {"name": "--version", "alias": "-v", "type": "boolean", "description": "Show version"}
        \\  ],
        \\  "commands": [
        \\    {
        \\      "name": "read",
        \\      "summary": "Read env vars (masked by default)",
        \\      "args": [{"name": "path_or_key", "required": false, "description": "Directory/file path, or a single KEY to look up"}],
        \\      "flags": [{"name": "--unmask", "alias": "-u", "type": "string", "repeatable": true, "description": "Reveal raw value of the given key"}],
        \\      "supports_json": true
        \\    },
        \\    {
        \\      "name": "write",
        \\      "summary": "Write KEY=value pairs (defaults to .env.local). Reads KEY=value lines from stdin if no args.",
        \\      "args": [{"name": "pairs", "required": false, "variadic": true, "description": "One or more KEY=value pairs"}],
        \\      "flags": [
        \\        {"name": "--file", "alias": "-f", "type": "string", "description": "Target file (default: .env.local)"},
        \\        {"name": "--force", "alias": "-y", "type": "boolean", "description": "Overwrite existing keys (--yes is an alias)"},
        \\        {"name": "--dry-run", "alias": "-n", "type": "boolean", "description": "Preview changes without writing"}
        \\      ],
        \\      "supports_json": true,
        \\      "json_output": {"written": [{"key": "string"}], "file": "string", "dry_run": "boolean"}
        \\    },
        \\    {
        \\      "name": "delete",
        \\      "summary": "Delete keys (defaults to .env.local)",
        \\      "args": [{"name": "keys", "required": true, "variadic": true, "description": "One or more keys to delete"}],
        \\      "flags": [
        \\        {"name": "--file", "alias": "-f", "type": "string", "description": "Target file (default: .env.local)"},
        \\        {"name": "--dry-run", "alias": "-n", "type": "boolean", "description": "Preview changes without writing"}
        \\      ],
        \\      "supports_json": true,
        \\      "json_output": {"deleted": ["string"], "not_found": ["string"], "file": "string", "dry_run": "boolean"}
        \\    },
        \\    {
        \\      "name": "diff",
        \\      "summary": "Compare two .env files/directories",
        \\      "args": [
        \\        {"name": "path1", "required": true, "description": "First path"},
        \\        {"name": "path2", "required": true, "description": "Second path"}
        \\      ],
        \\      "flags": [],
        \\      "supports_json": true,
        \\      "json_output": {"diff": [{"key": "string", "status": "added|removed|changed"}]}
        \\    },
        \\    {
        \\      "name": "list",
        \\      "summary": "List all keys (no values)",
        \\      "args": [],
        \\      "flags": [],
        \\      "supports_json": true,
        \\      "json_output": {"keys": ["string"]}
        \\    },
        \\    {
        \\      "name": "copy",
        \\      "aliases": ["cp"],
        \\      "summary": "Copy env vars from a source (file/dir) into a destination .env file. Real values are copied but never printed.",
        \\      "args": [
        \\        {"name": "source", "required": true, "description": "Path to copy from (file or directory)"},
        \\        {"name": "dest", "required": true, "description": "Destination .env file"},
        \\        {"name": "keys", "required": false, "variadic": true, "description": "Optional keys to copy (default: all)"}
        \\      ],
        \\      "flags": [
        \\        {"name": "--force", "alias": "-y", "type": "boolean", "description": "Overwrite keys that already exist in the destination"},
        \\        {"name": "--dry-run", "alias": "-n", "type": "boolean", "description": "Preview without writing"}
        \\      ],
        \\      "supports_json": true,
        \\      "json_output": {"copied": ["string"], "skipped": ["string"], "not_found": ["string"], "from": "string", "to": "string", "dry_run": "boolean"}
        \\    },
        \\    {
        \\      "name": "exec",
        \\      "aliases": ["run"],
        \\      "summary": "Run a command with the real env vars injected into its environment. Values are passed to the child process only and never printed.",
        \\      "args": [{"name": "command", "required": true, "variadic": true, "description": "Command and args, optionally after a -- separator"}],
        \\      "flags": [{"name": "--file", "alias": "-f", "type": "string", "description": "Load from a specific file/dir instead of discovering .env*"}],
        \\      "usage": "enever exec [-f FILE] -- <command> [args...]",
        \\      "supports_json": false,
        \\      "notes": "Exit code is the child's. 127 = command not found, 126 = not executable."
        \\    },
        \\    {
        \\      "name": "schema",
        \\      "summary": "Print this machine-readable CLI schema (always JSON)",
        \\      "args": [],
        \\      "flags": [],
        \\      "supports_json": true
        \\    },
        \\    {"name": "help", "summary": "Show help", "args": [], "flags": [], "supports_json": false},
        \\    {"name": "version", "summary": "Show version", "args": [], "flags": [], "supports_json": true}
        \\  ],
        \\  "exit_codes": [
        \\    {"code": 0, "name": "success", "description": "Command completed successfully"},
        \\    {"code": 1, "name": "general_error", "description": "Runtime failure (I/O, load, write)"},
        \\    {"code": 2, "name": "not_found", "description": "Requested key was not found"},
        \\    {"code": 3, "name": "key_exists", "description": "write without --force hit an existing key"},
        \\    {"code": 64, "name": "usage_error", "description": "Invalid arguments or usage"}
        \\  ],
        \\  "error_codes": ["USAGE", "KEY_NOT_FOUND", "KEY_EXISTS", "FILE_NOT_FOUND", "LOAD_FAILED", "READ_FAILED", "WRITE_FAILED", "STDIN_READ_FAILED", "OUTPUT_FAILED", "COMMAND_NOT_FOUND", "COMMAND_NOT_EXECUTABLE", "EXEC_FAILED"],
        \\  "error_envelope": {"error": {"code": "string", "message": "string", "hint": "string (optional)"}}
        \\}
        \\
    ;

    var obuf: [8192]u8 = undefined;
    var fw = getStdOut().writer(g_io, &obuf);
    const w = &fw.interface;
    w.writeAll(prefix) catch return ExitCode.general_error;
    w.writeAll(version) catch return ExitCode.general_error;
    w.writeAll(suffix) catch return ExitCode.general_error;
    w.flush() catch return ExitCode.general_error;
    return ExitCode.success;
}

fn printHelp() void {
    writeBytes(getStdOut(),
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
        \\  copy <src> <dst>    Copy env vars from src into dst (.env file)
        \\  exec -- <cmd>       Run <cmd> with real env vars injected (never printed)
        \\  schema              Print machine-readable CLI schema (JSON, for agents)
        \\  help                Show this help message
        \\  version             Show version
        \\
        \\Options:
        \\  -u, --unmask <key>  Show raw value of a key
        \\  -f, --file <path>   Target file for write/delete (default: .env.local)
        \\  --force, -y, --yes  Overwrite existing keys (write command)
        \\  -n, --dry-run       Preview write/delete without modifying files
        \\  --json              Output in JSON format (structured errors on stderr)
        \\  --no-color          Disable color (no-op; never emits color)
        \\  -q, --quiet         Suppress non-essential output
        \\  -h, --help          Show help
        \\  -v, --version       Show version
        \\
        \\Exit Codes:
        \\  0   Success
        \\  1   General error
        \\  2   Key not found
        \\  3   Key exists (write without --force)
        \\  64  Usage error (invalid arguments)
        \\
        \\Agent usage:
        \\  Run `enever schema` for a machine-readable description of every
        \\  command, flag, and exit code. Pass --json to any command for
        \\  structured output and structured errors.
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
        \\  enever copy .env .env.staging # Copy all keys into another file
        \\  enever copy ./svc .env API_KEY  # Copy one key from another project
        \\  enever exec -- npm run dev    # Run a command with secrets injected
        \\  enever exec -f .env.prod -- node app.js
        \\
        \\Diff output:
        \\  + KEY  Only in second file
        \\  - KEY  Only in first file
        \\  ~ KEY  Different values
        \\
    );
}

// Tests
test "parse help flag" {
    // Basic sanity - this mainly tests compilation
    _ = printHelp;
}
