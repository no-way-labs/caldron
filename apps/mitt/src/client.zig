const std = @import("std");

pub const SendResult = union(enum) {
    delivered: struct { reply: ?[]const u8 },
    rejected: struct { reason: []const u8 },
    failed: struct { err: []const u8 },
    timeout,
};

pub const Payload = union(enum) {
    file: []const u8,
    stdin,
    text: []const u8,
};

const PayloadData = struct {
    data: []const u8,
    filename: []const u8,
};

pub fn send(allocator: std.mem.Allocator, url: []const u8, payload: Payload, timeout_ms: u64) !SendResult {
    _ = timeout_ms;

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const uri = try std.Uri.parse(url);

    const payload_data = switch (payload) {
        .file => |path| blk: {
            const file = std.fs.cwd().openFile(path, .{}) catch |err| {
                const err_msg = try std.fmt.allocPrint(allocator, "Failed to open file: {}", .{err});
                return SendResult{ .failed = .{ .err = err_msg } };
            };
            defer file.close();

            const content = file.readToEndAlloc(allocator, 1024 * 1024 * 1024) catch |err| {
                const err_msg = try std.fmt.allocPrint(allocator, "Failed to read file: {}", .{err});
                return SendResult{ .failed = .{ .err = err_msg } };
            };
            break :blk PayloadData{ .data = content, .filename = std.fs.path.basename(path) };
        },
        .stdin => blk: {
            const stdin = std.io.getStdIn();
            const content = stdin.readToEndAlloc(allocator, 1024 * 1024 * 1024) catch |err| {
                const err_msg = try std.fmt.allocPrint(allocator, "Failed to read stdin: {}", .{err});
                return SendResult{ .failed = .{ .err = err_msg } };
            };
            break :blk PayloadData{ .data = content, .filename = "stdin" };
        },
        .text => |text| blk: {
            const content = try allocator.dupe(u8, text);
            break :blk PayloadData{ .data = content, .filename = "text" };
        },
    };
    defer allocator.free(payload_data.data);

    var header_buffer: [8192]u8 = undefined;
    var request = try client.open(.POST, uri, .{
        .server_header_buffer = &header_buffer,
        .extra_headers = &.{
            .{ .name = "x-filename", .value = payload_data.filename },
            .{ .name = "x-size", .value = try std.fmt.allocPrint(allocator, "{d}", .{payload_data.data.len}) },
            .{ .name = "content-type", .value = "application/octet-stream" },
        },
    });
    defer request.deinit();

    request.transfer_encoding = .{ .content_length = payload_data.data.len };

    try request.send();
    try request.writeAll(payload_data.data);
    try request.finish();

    try request.wait();

    const body = try request.reader().readAllAlloc(allocator, 1024 * 1024);
    errdefer allocator.free(body);

    switch (request.response.status) {
        .ok => return SendResult{ .delivered = .{ .reply = body } },
        .forbidden => {
            const reason = try allocator.dupe(u8, body);
            allocator.free(body);
            return SendResult{ .rejected = .{ .reason = reason } };
        },
        .payload_too_large => {
            const reason = try allocator.dupe(u8, body);
            allocator.free(body);
            return SendResult{ .rejected = .{ .reason = reason } };
        },
        else => {
            const err_msg = try std.fmt.allocPrint(allocator, "HTTP {d}: {s}", .{ @intFromEnum(request.response.status), body });
            allocator.free(body);
            return SendResult{ .failed = .{ .err = err_msg } };
        },
    }
}
