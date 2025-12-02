const std = @import("std");

pub const SaveResult = struct {
    path: []const u8,
    bytes: u64,
};

pub fn save(allocator: std.mem.Allocator, dir: []const u8, filename: []const u8, reader: std.io.AnyReader) !SaveResult {
    std.fs.cwd().makePath(dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    var dir_handle = try std.fs.cwd().openDir(dir, .{});
    defer dir_handle.close();

    const final_filename = try findAvailableFilename(allocator, dir_handle, filename);
    defer allocator.free(final_filename);

    var file = try dir_handle.createFile(final_filename, .{});
    defer file.close();

    var bytes_written: u64 = 0;
    var buffer: [8192]u8 = undefined;

    while (true) {
        const bytes_read = try reader.read(&buffer);
        if (bytes_read == 0) break;

        try file.writeAll(buffer[0..bytes_read]);
        bytes_written += bytes_read;
    }

    const full_path = try std.fs.path.join(allocator, &[_][]const u8{ dir, final_filename });

    return SaveResult{
        .path = full_path,
        .bytes = bytes_written,
    };
}

fn findAvailableFilename(allocator: std.mem.Allocator, dir: std.fs.Dir, filename: []const u8) ![]const u8 {
    dir.access(filename, .{}) catch {
        return try allocator.dupe(u8, filename);
    };

    const ext_index = std.mem.lastIndexOfScalar(u8, filename, '.');
    const base = if (ext_index) |idx| filename[0..idx] else filename;
    const ext = if (ext_index) |idx| filename[idx..] else "";

    var counter: u32 = 1;
    while (counter < 10000) : (counter += 1) {
        const candidate = try std.fmt.allocPrint(allocator, "{s}_{d}{s}", .{ base, counter, ext });
        errdefer allocator.free(candidate);

        dir.access(candidate, .{}) catch {
            return candidate;
        };

        allocator.free(candidate);
    }

    return error.TooManyCollisions;
}

test "save writes file to disk" {
    const allocator = std.testing.allocator;
    const test_dir = "test_inbox";
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    const data = "Hello, World!";
    var fbs = std.io.fixedBufferStream(data);
    const reader = fbs.reader().any();

    const result = try save(allocator, test_dir, "test.txt", reader);
    defer allocator.free(result.path);

    try std.testing.expectEqual(@as(u64, data.len), result.bytes);

    const file = try std.fs.cwd().openFile(result.path, .{});
    defer file.close();
    const content = try file.readToEndAlloc(allocator, 1024);
    defer allocator.free(content);

    try std.testing.expectEqualStrings(data, content);
}

test "save handles filename collisions" {
    const allocator = std.testing.allocator;
    const test_dir = "test_inbox_collision";
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    const data1 = "First file";
    var fbs1 = std.io.fixedBufferStream(data1);
    const result1 = try save(allocator, test_dir, "test.txt", fbs1.reader().any());
    defer allocator.free(result1.path);

    const data2 = "Second file";
    var fbs2 = std.io.fixedBufferStream(data2);
    const result2 = try save(allocator, test_dir, "test.txt", fbs2.reader().any());
    defer allocator.free(result2.path);

    try std.testing.expect(!std.mem.eql(u8, result1.path, result2.path));

    const file2 = try std.fs.cwd().openFile(result2.path, .{});
    defer file2.close();
    const content2 = try file2.readToEndAlloc(allocator, 1024);
    defer allocator.free(content2);

    try std.testing.expectEqualStrings(data2, content2);
}
