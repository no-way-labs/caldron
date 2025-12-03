const std = @import("std");

pub const Tunnel = struct {
    public_host: []const u8,
    public_port: u16,
    requested_port: u16,
    process: std.process.Child,
    allocator: std.mem.Allocator,

    pub fn establish(allocator: std.mem.Allocator, local_port: u16, bore_port: u16) !Tunnel {
        return try establishBore(allocator, local_port, bore_port);
    }

    pub fn shutdown(self: *Tunnel) void {
        _ = self.process.kill() catch {};
        self.allocator.free(self.public_host);
    }
};

fn establishBore(allocator: std.mem.Allocator, local_port: u16, bore_port: u16) !Tunnel {
    const port_str = try std.fmt.allocPrint(allocator, "{d}", .{local_port});
    defer allocator.free(port_str);

    const bore_port_str = try std.fmt.allocPrint(allocator, "{d}", .{bore_port});
    defer allocator.free(bore_port_str);

    const args = if (bore_port > 0)
        &[_][]const u8{
            "bore",
            "local",
            port_str,
            "--to",
            "bore.pub",
            "--port",
            bore_port_str,
        }
    else
        &[_][]const u8{
            "bore",
            "local",
            port_str,
            "--to",
            "bore.pub",
        };

    var process = std.process.Child.init(args, allocator);

    process.stdout_behavior = .Pipe;
    process.stderr_behavior = .Pipe;

    try process.spawn();

    var stdout_buffer: [4096]u8 = undefined;
    var total_read: usize = 0;

    const stdout = process.stdout.?;
    var timeout_counter: u32 = 0;
    const max_timeout: u32 = 100;

    while (timeout_counter < max_timeout) : (timeout_counter += 1) {
        const bytes_read = stdout.read(stdout_buffer[total_read..]) catch |err| {
            _ = process.kill() catch {};
            return err;
        };

        if (bytes_read > 0) {
            total_read += bytes_read;
            const output = stdout_buffer[0..total_read];

            // Look for "listening at bore.pub:PORT"
            if (std.mem.indexOf(u8, output, "listening at bore.pub:")) |pos| {
                const port_start = pos + "listening at bore.pub:".len;
                const port_end_opt = std.mem.indexOfScalarPos(u8, output, port_start, '\n');
                const port_end = port_end_opt orelse output.len;

                const port_str_extracted = std.mem.trim(u8, output[port_start..port_end], &std.ascii.whitespace);
                const public_port = try std.fmt.parseInt(u16, port_str_extracted, 10);

                const public_host = try allocator.dupe(u8, "bore.pub");

                return Tunnel{
                    .public_host = public_host,
                    .public_port = public_port,
                    .requested_port = bore_port,
                    .process = process,
                    .allocator = allocator,
                };
            }
        }

        std.Thread.sleep(100 * std.time.ns_per_ms);
    }

    _ = process.kill() catch {};
    return error.TunnelTimeout;
}
