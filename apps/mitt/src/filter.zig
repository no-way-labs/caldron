const std = @import("std");

pub const Filter = struct {
    accept_globs: ?[]const []const u8,
    reject_globs: ?[]const []const u8,
    max_size: u64,

    pub fn check(self: Filter, filename: []const u8, size: u64, content_type: []const u8) FilterResult {
        _ = content_type;

        if (size > self.max_size) {
            return FilterResult{ .rejected_size = .{ .max = self.max_size, .got = size } };
        }

        if (self.reject_globs) |reject| {
            for (reject) |pattern| {
                if (matchesGlob(filename, pattern)) {
                    return FilterResult{ .rejected_extension = pattern };
                }
            }
        }

        if (self.accept_globs) |accept| {
            var matched = false;
            for (accept) |pattern| {
                if (matchesGlob(filename, pattern)) {
                    matched = true;
                    break;
                }
            }
            if (!matched) {
                return FilterResult{ .rejected_extension = "not in accept list" };
            }
        }

        return FilterResult.ok;
    }
};

pub const FilterResult = union(enum) {
    ok,
    rejected_extension: []const u8,
    rejected_size: struct { max: u64, got: u64 },
    rejected_type: []const u8,
};

fn matchesGlob(filename: []const u8, pattern: []const u8) bool {
    if (std.mem.startsWith(u8, pattern, "*.")) {
        const ext = pattern[1..];
        return std.mem.endsWith(u8, filename, ext);
    }
    return std.mem.eql(u8, filename, pattern);
}

test "filter accepts file within size limit" {
    const filter = Filter{
        .accept_globs = null,
        .reject_globs = null,
        .max_size = 1000,
    };

    const result = filter.check("test.txt", 500, "text/plain");
    try std.testing.expect(result == .ok);
}

test "filter rejects file over size limit" {
    const filter = Filter{
        .accept_globs = null,
        .reject_globs = null,
        .max_size = 1000,
    };

    const result = filter.check("test.txt", 2000, "text/plain");
    try std.testing.expect(result == .rejected_size);
    try std.testing.expectEqual(@as(u64, 1000), result.rejected_size.max);
    try std.testing.expectEqual(@as(u64, 2000), result.rejected_size.got);
}

test "filter accepts matching extension" {
    const accept = [_][]const u8{"*.txt"};
    const filter = Filter{
        .accept_globs = &accept,
        .reject_globs = null,
        .max_size = 1000,
    };

    const result = filter.check("test.txt", 500, "text/plain");
    try std.testing.expect(result == .ok);
}

test "filter rejects non-matching extension" {
    const accept = [_][]const u8{"*.txt"};
    const filter = Filter{
        .accept_globs = &accept,
        .reject_globs = null,
        .max_size = 1000,
    };

    const result = filter.check("test.exe", 500, "application/exe");
    try std.testing.expect(result == .rejected_extension);
}

test "filter rejects blacklisted extension" {
    const reject = [_][]const u8{"*.exe"};
    const filter = Filter{
        .accept_globs = null,
        .reject_globs = &reject,
        .max_size = 1000,
    };

    const result = filter.check("test.exe", 500, "application/exe");
    try std.testing.expect(result == .rejected_extension);
}
