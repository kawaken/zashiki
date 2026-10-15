const std = @import("std");
const Allocator = std.mem.Allocator;
const compat_file = @import("../lib/compat/file.zig");
const global = @import("../global.zig");
const os_file = @import("../os/file.zig");

const response_prefix = "/tmp/zashiki-cli-response-";

pub fn newResponsePath(alloc: Allocator) ![]u8 {
    var basename_buf: [os_file.random_basename_len]u8 = undefined;
    const basename = os_file.randomBasename(&basename_buf) catch unreachable;
    return try std.fmt.allocPrint(alloc, "{s}{s}", .{ response_prefix, basename });
}

/// Open a Zashiki URL and wait for the app's response file.
pub fn sendAndWaitForResponse(alloc: Allocator, url: []const u8, response_path: []const u8) ![]u8 {
    const app_path = try applicationPath(alloc);
    defer if (app_path) |value| alloc.free(value);

    var app_argv: [4][]const u8 = undefined;
    var default_argv: [2][]const u8 = undefined;
    const argv: []const []const u8 = if (app_path) |app| blk: {
        app_argv = .{ "/usr/bin/open", "-a", app, url };
        break :blk &app_argv;
    } else blk: {
        default_argv = .{ "/usr/bin/open", url };
        break :blk &default_argv;
    };

    var child = try std.process.spawn(global.io(), .{
        .argv = argv,
        .stdout = .ignore,
        .stderr = .inherit,
    });
    const term = try child.wait(global.io());
    switch (term) {
        .exited => |code| if (code != 0) return error.OpenFailed,
        .signal, .stopped, .unknown => return error.OpenFailed,
    }

    return try waitForResponse(alloc, response_path);
}

pub fn appendQueryComponent(writer: *std.Io.Writer, value: []const u8) !void {
    const hex = "0123456789ABCDEF";
    for (value) |byte| {
        if (isUnreserved(byte)) {
            try writer.writeByte(byte);
        } else {
            try writer.writeByte('%');
            try writer.writeByte(hex[byte >> 4]);
            try writer.writeByte(hex[byte & 0x0f]);
        }
    }
}

fn waitForResponse(alloc: Allocator, path: []const u8) ![]u8 {
    for (0..200) |_| {
        const file = std.Io.Dir.openFileAbsolute(global.io(), path, .{ .mode = .read_only }) catch |err| switch (err) {
            error.FileNotFound => {
                try std.Io.sleep(global.io(), .fromMilliseconds(50), .awake);
                continue;
            },
            else => return err,
        };
        defer file.close(global.io());
        return try compat_file.readToEndAlloc(file, alloc, 1024);
    }
    return error.ResponseTimeout;
}

fn applicationPath(alloc: Allocator) !?[]u8 {
    if (try global.environ().containsUnempty(alloc, "ZASHIKI_APP")) {
        return try global.environ().getAlloc(alloc, "ZASHIKI_APP");
    }

    var executable_buf: [std.fs.max_path_bytes]u8 = undefined;
    const executable = executable_buf[0..try std.process.executablePath(global.io(), &executable_buf)];
    const executable_dir = std.fs.path.dirname(executable) orelse return null;
    const contents_dir = std.fs.path.dirname(executable_dir) orelse return null;
    const app_path = std.fs.path.dirname(contents_dir) orelse return null;
    if (!std.mem.endsWith(u8, app_path, ".app")) return null;
    return try alloc.dupe(u8, app_path);
}

fn isUnreserved(byte: u8) bool {
    return switch (byte) {
        'a'...'z', 'A'...'Z', '0'...'9', '-', '.', '_', '~' => true,
        else => false,
    };
}
