const std = @import("std");

pub fn main() !void {
    std.debug.print("Available: {any}\n", .{@typeInfo(std.crypto.aead)});
}
