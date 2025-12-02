const std = @import("std");
const filter = @import("filter.zig");
const storage = @import("storage.zig");
const config = @import("config.zig");
const crypto = @import("crypto.zig");

// TCP Protocol:
// [filename_len: u16][filename: bytes][encrypted_size: u64][nonce: 24 bytes][tag: 16 bytes][encrypted_data: bytes]

pub const Server = struct {
    port: u16,
    config: ServerConfig,
    allocator: std.mem.Allocator,
    listener: std.net.Server,
    encryption_key: [32]u8,

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
        const stream = connection.stream;

        // Read filename length (u16)
        var filename_len_buf: [2]u8 = undefined;
        const n1 = try stream.readAll(&filename_len_buf);
        if (n1 != 2) return error.UnexpectedEOF;
        const filename_len = std.mem.readInt(u16, &filename_len_buf, .big);

        if (filename_len == 0 or filename_len > 1024) {
            return error.InvalidFilename;
        }

        // Read filename
        const filename = try self.allocator.alloc(u8, filename_len);
        defer self.allocator.free(filename);
        const n2 = try stream.readAll(filename);
        if (n2 != filename_len) return error.UnexpectedEOF;

        // Read encrypted data size (u64)
        var encrypted_size_buf: [8]u8 = undefined;
        const n3 = try stream.readAll(&encrypted_size_buf);
        if (n3 != 8) return error.UnexpectedEOF;
        const encrypted_size = std.mem.readInt(u64, &encrypted_size_buf, .big);

        // Check size limits before allocating
        const file_filter = filter.Filter{
            .accept_globs = self.config.accept,
            .reject_globs = self.config.reject,
            .max_size = self.config.max_size,
        };

        const filter_result = file_filter.check(filename, encrypted_size, "application/octet-stream");

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
        const n4 = try stream.readAll(&nonce);
        if (n4 != 24) return error.UnexpectedEOF;

        // Read tag
        var tag: [16]u8 = undefined;
        const n5 = try stream.readAll(&tag);
        if (n5 != 16) return error.UnexpectedEOF;

        // Read encrypted data
        const ciphertext = try self.allocator.alloc(u8, encrypted_size);
        defer self.allocator.free(ciphertext);
        const n6 = try stream.readAll(ciphertext);
        if (n6 != encrypted_size) return error.UnexpectedEOF;

        // Decrypt
        const encrypted_data = crypto.EncryptedData{
            .nonce = nonce,
            .ciphertext = ciphertext,
            .tag = tag,
            .allocator = self.allocator,
        };

        const plaintext = crypto.decrypt(self.allocator, encrypted_data, self.encryption_key) catch {
            std.debug.print("Decryption failed - wrong password?\n", .{});
            return error.DecryptionFailed;
        };
        defer self.allocator.free(plaintext);

        // Save or output
        if (self.config.to_stdout) {
            try std.io.getStdOut().writeAll(plaintext);
        } else {
            var fbs = std.io.fixedBufferStream(plaintext);
            const result = try storage.save(self.allocator, self.config.dir, filename, fbs.reader().any());
            defer self.allocator.free(result.path);

            std.debug.print("Received: {s} ({d} bytes) -> {s}\n", .{ filename, result.bytes, result.path });
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
