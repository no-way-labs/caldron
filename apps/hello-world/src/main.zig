const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const stdout = std.io.getStdOut().writer();

    if (args.len < 2) {
        try stdout.print("Hello, World!\n", .{});
        try stdout.print("Usage: {s} <name>\n", .{args[0]});
        return;
    }

    const name = args[1];
    try stdout.print("Hello, {s}!\n", .{name});
}
