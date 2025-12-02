const std = @import("std");

pub const Provider = enum {
    bore,
};

pub const Tunnel = struct {
    public_url: []const u8,
    id: []const u8,
    process: std.process.Child,
    allocator: std.mem.Allocator,

    pub fn establish(allocator: std.mem.Allocator, provider: Provider, local_port: u16, requested_id: ?[]const u8) !Tunnel {
        _ = requested_id;

        switch (provider) {
            .bore => return try establishBore(allocator, local_port),
        }
    }

    pub fn shutdown(self: *Tunnel) void {
        _ = self.process.kill() catch {};
        self.allocator.free(self.public_url);
        self.allocator.free(self.id);
    }
};

fn establishBore(allocator: std.mem.Allocator, local_port: u16) !Tunnel {
    const port_str = try std.fmt.allocPrint(allocator, "{d}", .{local_port});
    defer allocator.free(port_str);

    var process = std.process.Child.init(&[_][]const u8{
        "bore",
        "local",
        port_str,
        "--to",
        "bore.pub",
    }, allocator);

    process.stdout_behavior = .Pipe;
    process.stderr_behavior = .Pipe;

    try process.spawn();

    var stdout_buffer: [1024]u8 = undefined;
    var total_read: usize = 0;

    const stdout = process.stdout.?;
    var timeout_counter: u32 = 0;
    const max_timeout: u32 = 50;

    while (timeout_counter < max_timeout) : (timeout_counter += 1) {
        const bytes_read = stdout.read(stdout_buffer[total_read..]) catch |err| {
            _ = process.kill() catch {};
            return err;
        };

        if (bytes_read > 0) {
            total_read += bytes_read;
            const output = stdout_buffer[0..total_read];

            if (std.mem.indexOf(u8, output, "bore.pub")) |_| {
                const url = try extractBoreUrl(allocator, output);
                const id = try extractIdFromUrl(allocator, url);

                return Tunnel{
                    .public_url = url,
                    .id = id,
                    .process = process,
                    .allocator = allocator,
                };
            }
        }

        std.time.sleep(100 * std.time.ns_per_ms);
    }

    _ = process.kill() catch {};
    return error.TunnelTimeout;
}

fn extractBoreUrl(allocator: std.mem.Allocator, output: []const u8) ![]const u8 {
    if (std.mem.indexOf(u8, output, "https://")) |start| {
        var end = start + 8;
        while (end < output.len and !std.ascii.isWhitespace(output[end])) : (end += 1) {}

        return try allocator.dupe(u8, output[start..end]);
    }

    return error.UrlNotFound;
}

fn extractIdFromUrl(allocator: std.mem.Allocator, url: []const u8) ![]const u8 {
    if (std.mem.indexOf(u8, url, "://")) |scheme_end| {
        const after_scheme = url[scheme_end + 3 ..];

        if (std.mem.indexOf(u8, after_scheme, ".")) |dot| {
            return try allocator.dupe(u8, after_scheme[0..dot]);
        }
    }

    return error.InvalidUrl;
}
