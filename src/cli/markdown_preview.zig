const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Action = @import("ghostty.zig").Action;
const args = @import("args.zig");
const global = @import("../global.zig");

pub const Options = struct {
    pub fn deinit(self: Options) void {
        _ = self;
    }

    /// Enables `-h` and `--help` to work.
    pub fn help(self: Options) !void {
        _ = self;
        return Action.help_error;
    }
};

/// Open a Markdown file in the Zashiki preview pane.
///
/// Usage:
///
///   zashiki +markdown-preview path/to/file.md
///
/// The path is resolved to an absolute path and sent to the running Zashiki
/// instance through its `zashiki://` URL handler. When the command runs from
/// a Zashiki shell, `ZASHIKI_SURFACE_ID` is also forwarded so the preview can
/// be associated with the originating terminal window.
pub fn run(alloc: Allocator) !u8 {
    if (comptime builtin.target.os.tag != .macos) {
        var stderr_buffer: [1024]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(global.io(), &stderr_buffer);
        try stderr_writer.interface.writeAll(
            "The `zashiki +markdown-preview` command is only supported on macOS.\n",
        );
        try stderr_writer.end();
        return 1;
    }

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(global.io(), &stderr_buffer);
    const stderr = &stderr_writer.interface;

    const path = parsePath(alloc) catch |err| switch (err) {
        Action.help_error => return err,
        else => {
            try stderr.writeAll("Usage: zashiki +markdown-preview <file.md>\n");
            return 1;
        },
    };

    var absolute_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const absolute_path_len = std.Io.Dir.cwd().realPathFile(
        global.io(),
        path,
        &absolute_path_buf,
    ) catch |err| {
        try stderr.print("zashiki +markdown-preview: cannot resolve '{s}': {}\n", .{ path, err });
        return 1;
    };
    const absolute_path = absolute_path_buf[0..absolute_path_len];

    var file = std.Io.Dir.openFileAbsolute(global.io(), absolute_path, .{}) catch |err| {
        try stderr.print("zashiki +markdown-preview: cannot open '{s}': {}\n", .{ absolute_path, err });
        return 1;
    };
    defer file.close(global.io());

    const stat = file.stat(global.io()) catch |err| {
        try stderr.print("zashiki +markdown-preview: cannot inspect '{s}': {}\n", .{ absolute_path, err });
        return 1;
    };
    if (stat.kind != .file) {
        try stderr.print("zashiki +markdown-preview: '{s}' is not a regular file\n", .{absolute_path});
        return 1;
    }

    const surface_id = if (try global.environ().containsUnempty(alloc, "ZASHIKI_SURFACE_ID"))
        try global.environ().getAlloc(alloc, "ZASHIKI_SURFACE_ID")
    else
        null;
    defer if (surface_id) |value| alloc.free(value);

    const url = try buildURL(alloc, absolute_path, surface_id);
    defer alloc.free(url);

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

    var child = std.process.spawn(global.io(), .{
        .argv = argv,
        .stdout = .ignore,
        .stderr = .inherit,
    }) catch |err| {
        try stderr.print("zashiki +markdown-preview: failed to run open: {}\n", .{err});
        return 1;
    };

    const term = child.wait(global.io()) catch |err| {
        try stderr.print("zashiki +markdown-preview: failed waiting for open: {}\n", .{err});
        return 1;
    };

    return switch (term) {
        .exited => |code| code,
        .signal => 1,
        .stopped, .unknown => 1,
    };
}

fn parsePath(alloc: Allocator) ![]const u8 {
    var iter = try args.argsIterator(alloc, global.args());
    defer iter.deinit();

    var path: ?[]const u8 = null;
    var end_of_options = false;
    while (iter.next()) |arg| {
        if (!end_of_options and (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h"))) {
            return Action.help_error;
        }
        if (!end_of_options and std.mem.eql(u8, arg, "--")) {
            end_of_options = true;
            continue;
        }
        if (!end_of_options and std.mem.startsWith(u8, arg, "-")) return error.InvalidArgument;
        if (path != null) return error.MultiplePaths;
        path = arg;
    }

    return path orelse error.MissingPath;
}

fn buildURL(alloc: Allocator, path: []const u8, surface_id: ?[]const u8) ![]u8 {
    var buffer: std.Io.Writer.Allocating = .init(alloc);
    defer buffer.deinit();

    try buffer.writer.writeAll("zashiki://markdown-preview/open?path=");
    try appendQueryComponent(&buffer.writer, path);
    if (surface_id) |surface| {
        if (isSurfaceID(surface)) {
            try buffer.writer.writeAll("&surface=");
            try appendQueryComponent(&buffer.writer, surface);
        }
    }
    return buffer.toOwnedSlice();
}

fn appendQueryComponent(writer: *std.Io.Writer, value: []const u8) !void {
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

fn isUnreserved(byte: u8) bool {
    return switch (byte) {
        'a'...'z', 'A'...'Z', '0'...'9', '-', '.', '_', '~' => true,
        else => false,
    };
}

fn isSurfaceID(value: []const u8) bool {
    if (value.len != 18 or !std.mem.startsWith(u8, value, "0x")) return false;
    for (value[2..]) |byte| {
        if (!std.ascii.isHex(byte)) return false;
    }
    return true;
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

test "build markdown preview URL" {
    const url = try buildURL(
        std.testing.allocator,
        "/tmp/日本語 notes.md?draft=true#section",
        "0x0123456789abcdef",
    );
    defer std.testing.allocator.free(url);

    try std.testing.expectEqualStrings(
        "zashiki://markdown-preview/open?path=%2Ftmp%2F%E6%97%A5%E6%9C%AC%E8%AA%9E%20notes.md%3Fdraft%3Dtrue%23section&surface=0x0123456789abcdef",
        url,
    );
}

test "invalid surface IDs are omitted" {
    const url = try buildURL(std.testing.allocator, "/tmp/readme.md", "not-a-surface");
    defer std.testing.allocator.free(url);

    try std.testing.expectEqualStrings(
        "zashiki://markdown-preview/open?path=%2Ftmp%2Freadme.md",
        url,
    );
}
