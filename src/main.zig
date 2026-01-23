const std = @import("std");
const builtin = @import("builtin");
const cli = @import("cli.zig");
const env_parser = @import("env-parser.zig");
const masking = @import("masking.zig");
const output = @import("output.zig");

pub const EnvEntry = env_parser.EnvEntry;
pub const EnvStore = env_parser.EnvStore;
pub const MaskStatus = masking.MaskStatus;

// Zig version compatibility helper for stderr
fn getStdErr() std.fs.File {
    if (comptime builtin.zig_version.order(.{ .major = 0, .minor = 14, .patch = 0 }) == .gt) {
        return std.fs.File.stderr();
    } else {
        return std.io.getStdErr();
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const result = cli.run(allocator) catch |err| {
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Error: {}\n", .{err}) catch "Error occurred\n";
        getStdErr().writeAll(msg) catch {};
        std.process.exit(1);
    };

    std.process.exit(result);
}

test {
    _ = @import("env-parser.zig");
    _ = @import("masking.zig");
    _ = @import("output.zig");
    _ = @import("cli.zig");
}
