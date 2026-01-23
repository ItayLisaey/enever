const std = @import("std");
const cli = @import("cli.zig");
const env_parser = @import("env-parser.zig");
const masking = @import("masking.zig");
const output = @import("output.zig");

pub const EnvEntry = env_parser.EnvEntry;
pub const EnvStore = env_parser.EnvStore;
pub const MaskStatus = masking.MaskStatus;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const result = cli.run(allocator) catch |err| {
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Error: {}\n", .{err}) catch "Error occurred\n";
        std.fs.File.stderr().writeAll(msg) catch {};
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
