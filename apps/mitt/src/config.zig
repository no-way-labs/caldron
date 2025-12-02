const std = @import("std");
const tunnel = @import("tunnel.zig");

pub const Config = struct {
    default_provider: tunnel.Provider = .bore,
    default_dir: []const u8 = "./inbox",
    max_size: u64 = 100 * 1024 * 1024,
    accept: ?[]const []const u8 = null,
    reject: ?[]const []const u8 = null,

    pub fn load() Config {
        return Config{};
    }
};
