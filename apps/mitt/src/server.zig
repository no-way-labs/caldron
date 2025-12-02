const std = @import("std");
const filter = @import("filter.zig");
const storage = @import("storage.zig");
const config = @import("config.zig");
const crypto = @import("crypto.zig");

// TCP Protocol:
// [filename_len: u16][filename: bytes][encrypted_size: u64][nonce: 24 bytes][tag: 16 bytes][encrypted_data: bytes]

/// Simple rate limiter to prevent abuse
const RateLimiter = struct {
    const ConnectionRecord = struct {
        count: u32,
        last_reset: i64,
    };

    connections: std.StringHashMap(ConnectionRecord),
    allocator: std.mem.Allocator,
    max_per_minute: u32,
    window_seconds: i64,

    fn init(allocator: std.mem.Allocator) RateLimiter {
        return .{
            .connections = std.StringHashMap(ConnectionRecord).init(allocator),
            .allocator = allocator,
            .max_per_minute = 10, // Max 10 connections per minute per IP
            .window_seconds = 60,
        };
    }

    fn deinit(self: *RateLimiter) void {
        var iter = self.connections.keyIterator();
        while (iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.connections.deinit();
    }

    fn checkAndUpdate(self: *RateLimiter, ip: []const u8) !bool {
        const now = std.time.timestamp();

        if (self.connections.get(ip)) |record| {
            const elapsed = now - record.last_reset;

            if (elapsed < self.window_seconds) {
                // Within the time window
                if (record.count >= self.max_per_minute) {
                    return false; // Rate limit exceeded
                }
                // Update count
                try self.connections.put(ip, .{
                    .count = record.count + 1,
                    .last_reset = record.last_reset,
                });
            } else {
                // Time window expired, reset counter
                try self.connections.put(ip, .{
                    .count = 1,
                    .last_reset = now,
                });
            }
        } else {
            // New IP
            const ip_copy = try self.allocator.dupe(u8, ip);
            try self.connections.put(ip_copy, .{
                .count = 1,
                .last_reset = now,
            });
        }

        return true; // Allowed
    }
};

/// Sanitizes a filename to prevent directory traversal attacks
/// Removes path separators and only keeps the base filename
fn sanitizeFilename(allocator: std.mem.Allocator, filename: []const u8) ![]const u8 {
    // Extract just the basename (everything after the last path separator)
    var basename = filename;

    // Find the last occurrence of / or \
    var i: usize = filename.len;
    while (i > 0) {
        i -= 1;
        if (filename[i] == '/' or filename[i] == '\\') {
            basename = filename[i + 1 ..];
            break;
        }
    }

    // Additional safety: reject filenames with .. or that start with .
    if (std.mem.indexOf(u8, basename, "..") != null) {
        return allocator.dupe(u8, "");
    }

    // Reject empty or hidden files (starting with .)
    if (basename.len == 0 or basename[0] == '.') {
        return allocator.dupe(u8, "");
    }

    // Only allow safe characters: alphanumeric, dash, underscore, dot
    for (basename) |c| {
        const is_safe = (c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            (c >= '0' and c <= '9') or
            c == '-' or c == '_' or c == '.';

        if (!is_safe) {
            // Replace unsafe characters with underscore
            // For now, just reject the file
            return allocator.dupe(u8, "");
        }
    }

    return allocator.dupe(u8, basename);
}

pub const Server = struct {
    port: u16,
    config: ServerConfig,
    allocator: std.mem.Allocator,
    listener: std.net.Server,
    encryption_key: [32]u8,
    rate_limiter: RateLimiter,
    active_connections: std.atomic.Value(u32),

    pub fn init(allocator: std.mem.Allocator, port: u16, server_config: ServerConfig, key: [32]u8) !Server {
        const address = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, port);
        const listener = try address.listen(.{
            .reuse_address = true,
        });

        return Server{
            .port = port,
            .config = server_config,
            .allocator = allocator,
            .listener = listener,
            .encryption_key = key,
            .rate_limiter = RateLimiter.init(allocator),
            .active_connections = std.atomic.Value(u32).init(0),
        };
    }

    pub fn run(self: *Server) !void {
        std.debug.print("Server listening on port {d}\n", .{self.port});

        while (true) {
            const connection = try self.listener.accept();
            defer connection.stream.close();

            // Check connection limit (max 5 concurrent connections)
            const current = self.active_connections.load(.monotonic);
            if (current >= 5) {
                std.debug.print("Connection limit reached, rejecting connection\n", .{});
                continue;
            }

            // Get IP address for rate limiting
            const addr = connection.address;
            var ip_buf: [64]u8 = undefined;
            const ip_str = std.fmt.bufPrint(&ip_buf, "{any}", .{addr}) catch "unknown";

            // Check rate limit
            const allowed = self.rate_limiter.checkAndUpdate(ip_str) catch false;
            if (!allowed) {
                std.debug.print("Rate limit exceeded for {s}\n", .{ip_str});
                continue;
            }

            // Increment connection counter
            _ = self.active_connections.fetchAdd(1, .monotonic);
            defer _ = self.active_connections.fetchSub(1, .monotonic);

            self.handleConnection(connection) catch |err| {
                std.debug.print("Error handling connection: {}\n", .{err});
            };
        }
    }

    pub fn shutdown(self: *Server) void {
        self.rate_limiter.deinit();
        self.listener.deinit();
    }

    fn handleConnection(self: *Server, connection: std.net.Server.Connection) !void {
        const stream = connection.stream;

        // Read filename length (u16)
        var filename_len_buf: [2]u8 = undefined;
        const n1 = try stream.readAtLeast(&filename_len_buf, 2);
        if (n1 != 2) return error.UnexpectedEOF;
        const filename_len = std.mem.readInt(u16, &filename_len_buf, .big);

        if (filename_len == 0 or filename_len > 1024) {
            return error.InvalidFilename;
        }

        // Read filename
        const filename = try self.allocator.alloc(u8, filename_len);
        defer self.allocator.free(filename);
        const n2 = try stream.readAtLeast(filename, filename_len);
        if (n2 != filename_len) return error.UnexpectedEOF;

        // Sanitize filename to prevent directory traversal attacks
        const sanitized_filename = try sanitizeFilename(self.allocator, filename);
        defer self.allocator.free(sanitized_filename);

        if (sanitized_filename.len == 0) {
            std.debug.print("Rejected: invalid filename\n", .{});
            return error.InvalidFilename;
        }

        // Read encrypted data size (u64)
        var encrypted_size_buf: [8]u8 = undefined;
        const n3 = try stream.readAtLeast(&encrypted_size_buf, 8);
        if (n3 != 8) return error.UnexpectedEOF;
        const encrypted_size = std.mem.readInt(u64, &encrypted_size_buf, .big);

        // Validate encrypted_size before any allocation to prevent DoS
        // Absolute maximum: 5GB to prevent memory exhaustion
        const ABSOLUTE_MAX_SIZE: u64 = 5 * 1024 * 1024 * 1024;
        if (encrypted_size == 0 or encrypted_size > ABSOLUTE_MAX_SIZE) {
            std.debug.print("Rejected: invalid size {d} bytes (max: {d} bytes)\n", .{ encrypted_size, ABSOLUTE_MAX_SIZE });
            return error.InvalidSize;
        }

        // Check size limits before allocating
        const file_filter = filter.Filter{
            .accept_globs = self.config.accept,
            .reject_globs = self.config.reject,
            .max_size = self.config.max_size,
        };

        const filter_result = file_filter.check(sanitized_filename, encrypted_size, "application/octet-stream");

        switch (filter_result) {
            .ok => {},
            .rejected_extension => |pattern| {
                std.debug.print("Rejected: file type not accepted: {s}\n", .{pattern});
                return;
            },
            .rejected_size => |info| {
                std.debug.print("Rejected: max size {d}mb, got {d}mb\n", .{ info.max / (1024 * 1024), info.got / (1024 * 1024) });
                return;
            },
            .rejected_type => |type_name| {
                std.debug.print("Rejected: content type not accepted: {s}\n", .{type_name});
                return;
            },
        }

        // Read nonce
        var nonce: [24]u8 = undefined;
        const n4 = try stream.readAtLeast(&nonce, 24);
        if (n4 != 24) return error.UnexpectedEOF;

        // Read tag
        var tag: [16]u8 = undefined;
        const n5 = try stream.readAtLeast(&tag, 16);
        if (n5 != 16) return error.UnexpectedEOF;

        // Read encrypted data
        const ciphertext = try self.allocator.alloc(u8, encrypted_size);
        defer self.allocator.free(ciphertext);
        const n6 = try stream.readAtLeast(ciphertext, encrypted_size);
        if (n6 != encrypted_size) return error.UnexpectedEOF;

        // Decrypt
        const encrypted_data = crypto.EncryptedData{
            .nonce = nonce,
            .ciphertext = ciphertext,
            .tag = tag,
            .allocator = self.allocator,
        };

        const plaintext = crypto.decrypt(self.allocator, encrypted_data, self.encryption_key) catch {
            // Add constant-time delay to prevent timing attacks
            // Attackers can't distinguish wrong password from network delay
            std.Thread.sleep(100 * std.time.ns_per_ms);
            std.debug.print("Authentication failed\n", .{});
            return error.AuthenticationFailed;
        };
        defer self.allocator.free(plaintext);

        // Zero plaintext memory before freeing (security best practice)
        defer std.crypto.secureZero(u8, plaintext);

        // Save or output
        if (self.config.to_stdout) {
            try std.fs.File.stdout().writeAll(plaintext);
        } else {
            var fbs = std.io.fixedBufferStream(plaintext);
            const result = try storage.save(self.allocator, self.config.dir, sanitized_filename, fbs.reader().any());
            defer self.allocator.free(result.path);

            std.debug.print("Received: {s} ({d} bytes) -> {s}\n", .{ sanitized_filename, result.bytes, result.path });
        }

        // Send acknowledgment (single byte: 0 = success)
        const ack: [1]u8 = .{0};
        try stream.writeAll(&ack);
    }
};

pub const ServerConfig = struct {
    dir: []const u8,
    to_stdout: bool,
    accept: ?[]const []const u8,
    reject: ?[]const []const u8,
    max_size: u64,
};
