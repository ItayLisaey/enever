const std = @import("std");

pub const MaskStatus = enum {
    public,
    masked,
};

// All values are masked by default - security first
pub fn getMaskStatus(_: []const u8) MaskStatus {
    return .masked;
}

pub fn maskValue(value: []const u8, buf: []u8) []const u8 {
    // Show last 4 characters, mask the rest
    // Format: ****xxxx (last 4 chars visible)

    if (value.len <= 4) {
        const asterisks = "****";
        @memcpy(buf[0..4], asterisks);
        return buf[0..4];
    }

    const visible_len: usize = 4;
    const asterisk_count: usize = 4;
    const total_len = asterisk_count + visible_len;

    if (total_len > buf.len) {
        return "****";
    }

    @memset(buf[0..asterisk_count], '*');
    const start = value.len - visible_len;
    @memcpy(buf[asterisk_count .. asterisk_count + visible_len], value[start..]);

    return buf[0..total_len];
}

// Tests
test "all values are masked" {
    try std.testing.expectEqual(MaskStatus.masked, getMaskStatus("API_URL"));
    try std.testing.expectEqual(MaskStatus.masked, getMaskStatus("PORT"));
    try std.testing.expectEqual(MaskStatus.masked, getMaskStatus("anything"));
}

test "mask value - long values" {
    var buf: [64]u8 = undefined;
    const result = maskValue("sk_live_abcd1234efgh5678", &buf);
    try std.testing.expectEqualStrings("****5678", result);
}

test "mask value - short values" {
    var buf: [64]u8 = undefined;
    const result = maskValue("abc", &buf);
    try std.testing.expectEqualStrings("****", result);
}
