const std = @import("std");
const server = @import("server.zig");
const client = @import("client.zig");
const tunnel = @import("tunnel.zig");
const id = @import("id.zig");
const config = @import("config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "open")) {
        try handleOpen(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "send")) {
        try handleSend(allocator, args[2..]);
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        try printUsage();
        std.process.exit(1);
    }
}

fn printUsage() !void {
    const usage =
        \\Usage: mitt <command> [options]
        \\
        \\Commands:
        \\  open              Start a server to receive files
        \\  send <id@provider> <payload>  Send a file to an open mitt
        \\
        \\Open options:
        \\  --port <port>     Local port (default: random)
        \\  --id <name>       Request specific ID
        \\  --via <provider>  Tunnel provider (default: bore)
        \\  --dir <path>      Save directory (default: ./inbox)
        \\  --stdout          Print to stdout instead of saving
        \\  --accept <globs>  Whitelist (e.g., *.txt,*.csv)
        \\  --reject <globs>  Blacklist (e.g., *.exe)
        \\  --max-size <bytes> Max file size (default: 100mb)
        \\
        \\Send options:
        \\  --text <string>   Send literal text
        \\  --timeout <seconds> Wait time (default: 30)
        \\
    ;
    try std.io.getStdErr().writeAll(usage);
}

fn handleOpen(allocator: std.mem.Allocator, args: []const [:0]const u8) !void {
    var port: u16 = 0;
    var requested_id: ?[]const u8 = null;
    var provider = tunnel.Provider.bore;
    var dir: []const u8 = "./inbox";
    var to_stdout = false;
    var accept: ?[]const []const u8 = null;
    var reject: ?[]const []const u8 = null;
    var max_size: u64 = 100 * 1024 * 1024;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--port") and i + 1 < args.len) {
            i += 1;
            port = try std.fmt.parseInt(u16, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--id") and i + 1 < args.len) {
            i += 1;
            requested_id = args[i];
        } else if (std.mem.eql(u8, arg, "--via") and i + 1 < args.len) {
            i += 1;
            if (std.mem.eql(u8, args[i], "bore")) {
                provider = .bore;
            }
        } else if (std.mem.eql(u8, arg, "--dir") and i + 1 < args.len) {
            i += 1;
            dir = args[i];
        } else if (std.mem.eql(u8, arg, "--stdout")) {
            to_stdout = true;
        } else if (std.mem.eql(u8, arg, "--accept") and i + 1 < args.len) {
            i += 1;
            accept = try parseGlobs(allocator, args[i]);
        } else if (std.mem.eql(u8, arg, "--reject") and i + 1 < args.len) {
            i += 1;
            reject = try parseGlobs(allocator, args[i]);
        } else if (std.mem.eql(u8, arg, "--max-size") and i + 1 < args.len) {
            i += 1;
            max_size = try std.fmt.parseInt(u64, args[i], 10);
        }
    }

    if (port == 0) {
        const address = try std.net.Address.parseIp4("127.0.0.1", 0);
        const socket = try std.posix.socket(address.any.family, std.posix.SOCK.STREAM, std.posix.IPPROTO.TCP);
        defer std.posix.close(socket);

        try std.posix.bind(socket, &address.any, address.getOsSockLen());
        try std.posix.listen(socket, 1);

        var sock_addr: std.net.Address = undefined;
        var sock_len = sock_addr.getOsSockLen();
        try std.posix.getsockname(socket, &sock_addr.any, &sock_len);

        port = sock_addr.in.getPort();
    }

    var srv = try server.Server.init(allocator, port, .{
        .dir = dir,
        .to_stdout = to_stdout,
        .accept = accept,
        .reject = reject,
        .max_size = max_size,
    });
    defer srv.shutdown();

    var tun = try tunnel.Tunnel.establish(allocator, provider, port, requested_id);
    defer tun.shutdown();

    std.debug.print("\nYour mitt: {s}@bore\n", .{tun.id});
    std.debug.print("Public URL: {s}\n", .{tun.public_url});
    std.debug.print("Waiting for files...\n\n", .{});

    try srv.run();
}

fn handleSend(allocator: std.mem.Allocator, args: []const [:0]const u8) !void {
    if (args.len < 2) {
        std.debug.print("Usage: mitt send <id@provider> <payload>\n", .{});
        std.process.exit(1);
    }

    const target = args[0];
    const payload_arg = args[1];

    var text_payload: ?[]const u8 = null;
    var timeout_seconds: u64 = 30;

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--text") and i + 1 < args.len) {
            i += 1;
            text_payload = args[i];
        } else if (std.mem.eql(u8, arg, "--timeout") and i + 1 < args.len) {
            i += 1;
            timeout_seconds = try std.fmt.parseInt(u64, args[i], 10);
        }
    }

    const url = try resolveTarget(allocator, target);
    defer allocator.free(url);

    const payload = if (text_payload) |text|
        client.Payload{ .text = text }
    else if (std.mem.eql(u8, payload_arg, "-"))
        client.Payload.stdin
    else
        client.Payload{ .file = payload_arg };

    const result = try client.send(allocator, url, payload, timeout_seconds * 1000);

    switch (result) {
        .delivered => |info| {
            std.debug.print("Delivered.\n", .{});
            if (info.reply) |reply| {
                allocator.free(reply);
            }
            std.process.exit(0);
        },
        .rejected => |info| {
            std.debug.print("Rejected: {s}\n", .{info.reason});
            allocator.free(info.reason);
            std.process.exit(1);
        },
        .failed => |info| {
            std.debug.print("Failed: {s}\n", .{info.err});
            allocator.free(info.err);
            std.process.exit(2);
        },
        .timeout => {
            std.debug.print("Timeout: server did not respond\n", .{});
            std.process.exit(2);
        },
    }
}

fn resolveTarget(allocator: std.mem.Allocator, target: []const u8) ![]const u8 {
    if (std.mem.indexOf(u8, target, "@")) |at_index| {
        const mitt_id = target[0..at_index];
        const provider_name = target[at_index + 1 ..];

        if (std.mem.eql(u8, provider_name, "bore")) {
            return try std.fmt.allocPrint(allocator, "https://{s}.bore.pub", .{mitt_id});
        }

        return error.UnsupportedProvider;
    }

    return error.InvalidTargetFormat;
}

fn parseGlobs(allocator: std.mem.Allocator, input: []const u8) ![]const []const u8 {
    var list = std.ArrayList([]const u8).init(allocator);
    errdefer list.deinit();

    var iter = std.mem.tokenizeScalar(u8, input, ',');
    while (iter.next()) |glob| {
        try list.append(glob);
    }

    return try list.toOwnedSlice();
}

test "simple test" {
    try std.testing.expect(true);
}
