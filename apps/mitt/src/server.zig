const std = @import("std");
const filter = @import("filter.zig");
const storage = @import("storage.zig");
const config = @import("config.zig");

pub const Server = struct {
    port: u16,
    config: ServerConfig,
    allocator: std.mem.Allocator,
    listener: std.net.Server,

    pub fn init(allocator: std.mem.Allocator, port: u16, server_config: ServerConfig) !Server {
        const address = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, port);
        const listener = try address.listen(.{
            .reuse_address = true,
        });

        return Server{
            .port = port,
            .config = server_config,
            .allocator = allocator,
            .listener = listener,
        };
    }

    pub fn run(self: *Server) !void {
        std.debug.print("Server listening on port {d}\n", .{self.port});

        while (true) {
            const connection = try self.listener.accept();
            defer connection.stream.close();

            self.handleConnection(connection) catch |err| {
                std.debug.print("Error handling connection: {}\n", .{err});
            };
        }
    }

    pub fn shutdown(self: *Server) void {
        self.listener.deinit();
    }

    fn handleConnection(self: *Server, connection: std.net.Server.Connection) !void {
        var buffer: [8192]u8 = undefined;
        var total_read: usize = 0;

        while (total_read < buffer.len) {
            const bytes_read = try connection.stream.read(buffer[total_read..]);
            if (bytes_read == 0) break;
            total_read += bytes_read;

            if (std.mem.indexOf(u8, buffer[0..total_read], "\r\n\r\n")) |_| {
                break;
            }
        }

        const request_text = buffer[0..total_read];

        if (!std.mem.startsWith(u8, request_text, "POST")) {
            try sendResponse(connection.stream, "405 Method Not Allowed", "Only POST requests are allowed");
            return;
        }

        const filename = extractHeader(request_text, "x-filename") orelse "unnamed";
        const size_str = extractHeader(request_text, "x-size") orelse "0";
        const content_type = extractHeader(request_text, "content-type") orelse "application/octet-stream";

        const size = std.fmt.parseInt(u64, size_str, 10) catch 0;

        const file_filter = filter.Filter{
            .accept_globs = self.config.accept,
            .reject_globs = self.config.reject,
            .max_size = self.config.max_size,
        };

        const filter_result = file_filter.check(filename, size, content_type);

        switch (filter_result) {
            .ok => {},
            .rejected_extension => |pattern| {
                const msg = try std.fmt.allocPrint(self.allocator, "{{\"error\": \"file type not accepted: {s}\"}}", .{pattern});
                defer self.allocator.free(msg);
                try sendResponse(connection.stream, "403 Forbidden", msg);
                return;
            },
            .rejected_size => |info| {
                const msg = try std.fmt.allocPrint(self.allocator, "{{\"error\": \"max size {d}mb, got {d}mb\"}}", .{ info.max / (1024 * 1024), info.got / (1024 * 1024) });
                defer self.allocator.free(msg);
                try sendResponse(connection.stream, "413 Payload Too Large", msg);
                return;
            },
            .rejected_type => |type_name| {
                const msg = try std.fmt.allocPrint(self.allocator, "{{\"error\": \"content type not accepted: {s}\"}}", .{type_name});
                defer self.allocator.free(msg);
                try sendResponse(connection.stream, "403 Forbidden", msg);
                return;
            },
        }

        if (std.mem.indexOf(u8, request_text, "\r\n\r\n")) |body_start| {
            const header_end = body_start + 4;
            const body_in_buffer = request_text[header_end..];

            if (self.config.to_stdout) {
                try std.io.getStdOut().writeAll(body_in_buffer);

                var read_buffer: [8192]u8 = undefined;
                var remaining = size - body_in_buffer.len;
                while (remaining > 0) {
                    const to_read = @min(remaining, read_buffer.len);
                    const bytes_read = try connection.stream.read(read_buffer[0..to_read]);
                    if (bytes_read == 0) break;
                    try std.io.getStdOut().writeAll(read_buffer[0..bytes_read]);
                    remaining -= bytes_read;
                }

                try sendResponse(connection.stream, "200 OK", "{\"status\": \"received\"}");
            } else {
                var body_list = std.ArrayList(u8).init(self.allocator);
                defer body_list.deinit();

                try body_list.appendSlice(body_in_buffer);

                var read_buffer: [8192]u8 = undefined;
                var remaining = size - body_in_buffer.len;
                while (remaining > 0) {
                    const to_read = @min(remaining, read_buffer.len);
                    const bytes_read = try connection.stream.read(read_buffer[0..to_read]);
                    if (bytes_read == 0) break;
                    try body_list.appendSlice(read_buffer[0..bytes_read]);
                    remaining -= bytes_read;
                }

                var fbs = std.io.fixedBufferStream(body_list.items);
                const result = try storage.save(self.allocator, self.config.dir, filename, fbs.reader().any());
                defer self.allocator.free(result.path);

                std.debug.print("Received: {s} ({d} bytes) -> {s}\n", .{ filename, result.bytes, result.path });

                const msg = try std.fmt.allocPrint(self.allocator, "{{\"status\": \"received\", \"filename\": \"{s}\", \"size\": {d}}}", .{ filename, result.bytes });
                defer self.allocator.free(msg);
                try sendResponse(connection.stream, "200 OK", msg);
            }
        }
    }
};

fn sendResponse(stream: std.net.Stream, status: []const u8, body: []const u8) !void {
    const response = try std.fmt.allocPrint(std.heap.page_allocator, "HTTP/1.1 {s}\r\nContent-Length: {d}\r\nContent-Type: application/json\r\n\r\n{s}", .{ status, body.len, body });
    defer std.heap.page_allocator.free(response);
    try stream.writeAll(response);
}

fn extractHeader(request: []const u8, name: []const u8) ?[]const u8 {
    var lines = std.mem.tokenizeScalar(u8, request, '\n');

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);

        if (std.mem.indexOf(u8, trimmed, ":")) |colon| {
            const header_name = std.mem.trim(u8, trimmed[0..colon], &std.ascii.whitespace);
            const header_value = std.mem.trim(u8, trimmed[colon + 1 ..], &std.ascii.whitespace);

            if (std.ascii.eqlIgnoreCase(header_name, name)) {
                return header_value;
            }
        }
    }

    return null;
}

pub const ServerConfig = struct {
    dir: []const u8,
    to_stdout: bool,
    accept: ?[]const []const u8,
    reject: ?[]const []const u8,
    max_size: u64,
};

pub const IncomingFile = struct {
    filename: []const u8,
    size: u64,
    content_type: []const u8,
    body_reader: std.io.AnyReader,
};

pub const HandleResult = union(enum) {
    accepted: struct { filename: []const u8, bytes_written: u64 },
    rejected: struct { code: u16, message: []const u8 },
};
