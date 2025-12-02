const std = @import("std");
const crypto = @import("crypto.zig");

pub const SendResult = union(enum) {
    delivered,
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

pub fn send(allocator: std.mem.Allocator, host: []const u8, port: u16, payload: Payload, key: [32]u8, timeout_ms: u64) !SendResult {
    // Load payload
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
            const stdin = std.fs.File.stdin();
            const content = stdin.readToEndAlloc(allocator, 1024 * 1024 * 1024) catch |err| {
                const err_msg = try std.fmt.allocPrint(allocator, "Failed to read stdin: {}", .{err});
                return SendResult{ .failed = .{ .err = err_msg } };
            };
            break :blk PayloadData{ .data = content, .filename = "stdin" };
        },
        .text => |text| blk: {
            const content = try allocator.dupe(u8, text);
            break :blk PayloadData{ .data = content, .filename = "text.txt" };
        },
    };
    defer allocator.free(payload_data.data);

    // Encrypt the data
    var encrypted = try crypto.encrypt(allocator, payload_data.data, key);
    defer encrypted.deinit();

    // Connect to server
    const stream = std.net.tcpConnectToHost(allocator, host, port) catch |err| {
        const err_msg = try std.fmt.allocPrint(allocator, "Connection failed to {s}:{d}: {}", .{ host, port, err });
        return SendResult{ .failed = .{ .err = err_msg } };
    };
    defer stream.close();

    // Set socket timeouts
    if (timeout_ms > 0) {
        const timeout_secs: u32 = @intCast(@min(timeout_ms / 1000, std.math.maxInt(u32)));
        const timeout_usecs: u32 = @intCast((timeout_ms % 1000) * 1000);

        const timeout = std.posix.timeval{
            .sec = @intCast(timeout_secs),
            .usec = @intCast(timeout_usecs),
        };

        // Set receive timeout
        std.posix.setsockopt(
            stream.handle,
            std.posix.SOL.SOCKET,
            std.posix.SO.RCVTIMEO,
            std.mem.asBytes(&timeout),
        ) catch |err| {
            std.debug.print("Warning: Failed to set receive timeout: {}\n", .{err});
        };

        // Set send timeout
        std.posix.setsockopt(
            stream.handle,
            std.posix.SOL.SOCKET,
            std.posix.SO.SNDTIMEO,
            std.mem.asBytes(&timeout),
        ) catch |err| {
            std.debug.print("Warning: Failed to set send timeout: {}\n", .{err});
        };
    }

    // Send filename length (u16)
    if (payload_data.filename.len > std.math.maxInt(u16)) {
        const err_msg = try std.fmt.allocPrint(allocator, "Filename too long", .{});
        return SendResult{ .failed = .{ .err = err_msg } };
    }

    var filename_len_buf: [2]u8 = undefined;
    std.mem.writeInt(u16, &filename_len_buf, @intCast(payload_data.filename.len), .big);
    try stream.writeAll(&filename_len_buf);

    // Send filename
    try stream.writeAll(payload_data.filename);

    // Send encrypted data size (u64)
    var encrypted_size_buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &encrypted_size_buf, encrypted.ciphertext.len, .big);
    try stream.writeAll(&encrypted_size_buf);

    // Send nonce
    try stream.writeAll(&encrypted.nonce);

    // Send tag
    try stream.writeAll(&encrypted.tag);

    // Send encrypted data
    try stream.writeAll(encrypted.ciphertext);

    // Read acknowledgment
    var ack: [1]u8 = undefined;
    const n = stream.readAtLeast(&ack, 1) catch {
        const err_msg = try std.fmt.allocPrint(allocator, "No acknowledgment from server", .{});
        return SendResult{ .failed = .{ .err = err_msg } };
    };
    if (n != 1) {
        const err_msg = try std.fmt.allocPrint(allocator, "No acknowledgment from server", .{});
        return SendResult{ .failed = .{ .err = err_msg } };
    }

    if (ack[0] == 0) {
        return SendResult.delivered;
    } else {
        const err_msg = try std.fmt.allocPrint(allocator, "Server rejected transfer", .{});
        return SendResult{ .failed = .{ .err = err_msg } };
    }
}
