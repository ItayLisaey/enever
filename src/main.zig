const std = @import("std");
const cli = @import("cli.zig");
const env_parser = @import("env-parser.zig");
const masking = @import("masking.zig");
const output = @import("output.zig");

pub const EnvEntry = env_parser.EnvEntry;
pub const EnvStore = env_parser.EnvStore;
pub const MaskStatus = masking.MaskStatus;

// Zig 0.16 main signature: the runtime provides an Io implementation, a general
// purpose allocator, the command-line arguments, and the environment map.
pub fn main(init: std.process.Init) u8 {
    return cli.run(init.io, init.gpa, init.minimal.args, init.environ_map) catch |err| {
        var buf: [256]u8 = undefined;
        var fw = std.Io.File.stderr().writer(init.io, &buf);
        fw.interface.print("Error: {s}\n", .{@errorName(err)}) catch {};
        fw.interface.flush() catch {};
        return 1;
    };
}

test {
    _ = @import("env-parser.zig");
    _ = @import("masking.zig");
    _ = @import("output.zig");
    _ = @import("cli.zig");
}
