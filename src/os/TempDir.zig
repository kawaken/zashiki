//! Creates a temporary directory at runtime that can be safely used to
//! store temporary data and is destroyed on deinit.
const TempDir = @This();

const builtin = @import("builtin");
const std = @import("std");
const Dir = std.Io.Dir;
const file = @import("file.zig");
const global = @import("../global.zig");

const log = std.log.scoped(.tempdir);

/// Dir is the directory handle
dir: Dir,

/// Parent directory
parent: Dir,

/// Name buffer that name points into. Generally do not use. To get the
/// name call the name() function.
name_buf: [file.random_basename_len:0]u8,

/// Create the temporary directory.
pub fn init() !TempDir {
    // Note: the tmp_path_buf sentinel is important because it ensures
    // we actually always have random_basename_len+1 bytes of available
    // space. We need that so we can set the sentinel in the case we use
    // all the possible length.
    var tmp_path_buf: [file.random_basename_len:0]u8 = undefined;

    const dir = dir: {
        const cwd = std.Io.Dir.cwd();
        const tmp_dir = try file.allocTmpDir(std.heap.page_allocator, global.environ());
        defer file.freeTmpDir(std.heap.page_allocator, tmp_dir);
        break :dir try cwd.openDir(global.io(), tmp_dir, .{});
    };
    errdefer dir.close(global.io());

    // We now loop forever until we can find a directory that we can create.
    while (true) {
        const tmp_path = try file.randomBasename(&tmp_path_buf);
        tmp_path_buf[tmp_path.len] = 0;

        dir.createDir(global.io(), tmp_path, .default_dir) catch |err| switch (err) {
            error.PathAlreadyExists => continue,
            else => |e| return e,
        };
        errdefer dir.deleteTree(global.io(), tmp_path) catch {};

        return TempDir{
            .dir = try dir.openDir(global.io(), tmp_path, .{}),
            .parent = dir,
            .name_buf = tmp_path_buf,
        };
    }
}

/// Name returns the name of the directory. This is just the basename
/// and is not the full absolute path.
pub fn name(self: *TempDir) []const u8 {
    return std.mem.sliceTo(&self.name_buf, 0);
}

/// Finish with the temporary directory. This deletes all contents in the
/// directory.
pub fn deinit(self: *TempDir) void {
    self.close(.delete);
}

pub const CloseMode = enum { delete, retain };

/// Close both handles. Retaining leaves the files available to consumers.
pub fn close(self: *TempDir, mode: CloseMode) void {
    self.dir.close(global.io());
    if (mode == .delete) self.parent.deleteTree(global.io(), self.name()) catch |err|
        log.err("error deleting temp dir err={}", .{err});
    self.parent.close(global.io());
}

// Repetition also catches descriptor reuse and success-path leaks.
test "TempDir closes handles and retains or deletes contents" {
    const testing = std.testing;
    for (0..128) |i| {
        var td = try init();
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = path_buf[0..try td.dir.realPath(testing.io, &path_buf)];
        const handles = [_]Dir.Handle{ td.dir.handle, td.parent.handle };
        {
            const f = try td.dir.createFile(testing.io, "screen.txt", .{});
            defer f.close(testing.io);
            try f.writeStreamingAll(testing.io, "terminal 日本語");
        }
        const retain = i % 2 == 0;
        td.close(if (retain) .retain else .delete);
        if (builtin.os.tag == .macos) {
            for (handles) |handle| {
                const result = std.posix.system.fcntl(handle, std.posix.F.GETFD);
                try testing.expectEqual(std.posix.E.BADF, std.posix.errno(result));
            }
        }
        if (retain) {
            defer Dir.cwd().deleteTree(testing.io, path) catch {};
            var dir = try Dir.openDirAbsolute(testing.io, path, .{});
            defer dir.close(testing.io);
            const contents = try dir.readFileAlloc(testing.io, "screen.txt", testing.allocator, .limited(1024));
            defer testing.allocator.free(contents);
            try testing.expectEqualStrings("terminal 日本語", contents);
        } else {
            try testing.expectError(error.FileNotFound, Dir.openDirAbsolute(testing.io, path, .{}));
        }
    }
}
