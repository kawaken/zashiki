const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Action = @import("ghostty.zig").Action;
const args = @import("args.zig");
const compat_file = @import("../lib/compat/file.zig");
const global = @import("../global.zig");
const os_file = @import("../os/file.zig");

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
/// instance through its `zashiki://` URL handler. The command waits for the
/// app to confirm that the preview pane opened. When the command runs from a
/// Zashiki shell, `ZASHIKI_SURFACE_ID` is also forwarded so the preview can
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

    var response_name_buf: [os_file.random_basename_len]u8 = undefined;
    const response_name = os_file.randomBasename(&response_name_buf) catch unreachable;
    const response_path = try std.fmt.allocPrint(
        alloc,
        "/tmp/zashiki-preview-response-{s}",
        .{response_name},
    );
    defer alloc.free(response_path);
    defer std.Io.Dir.deleteFileAbsolute(global.io(), response_path) catch {};

    const url = try buildURL(alloc, absolute_path, surface_id, response_path);
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

    switch (term) {
        .exited => |code| if (code != 0) return code,
        .signal, .stopped, .unknown => return 1,
    }

    const response = waitForResponse(alloc, response_path) catch |err| {
        try stderr.print(
            "zashiki +markdown-preview: Zashiki did not confirm opening the preview: {}\n",
            .{err},
        );
        return 1;
    };
    defer alloc.free(response);

    if (std.mem.eql(u8, response, "opened")) {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(global.io(), &stdout_buffer);
        try stdout_writer.interface.print("Markdown preview opened: {s}\n", .{absolute_path});
        try stdout_writer.end();
        return 0;
    }

    const reason = if (std.mem.startsWith(u8, response, "error:"))
        response["error:".len..]
    else
        "invalid-response";
    try stderr.print("zashiki +markdown-preview: Zashiki rejected the preview request ({s})\n", .{reason});
    return 1;
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

fn buildURL(alloc: Allocator, path: []const u8, surface_id: ?[]const u8, response_path: []const u8) ![]u8 {
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
    try buffer.writer.writeAll("&response=");
    try appendQueryComponent(&buffer.writer, response_path);
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
        "/tmp/zashiki-preview-response-abcdefghijklmnopqrstuv",
    );
    defer std.testing.allocator.free(url);

    try std.testing.expectEqualStrings(
        "zashiki://markdown-preview/open?path=%2Ftmp%2F%E6%97%A5%E6%9C%AC%E8%AA%9E%20notes.md%3Fdraft%3Dtrue%23section&surface=0x0123456789abcdef&response=%2Ftmp%2Fzashiki-preview-response-abcdefghijklmnopqrstuv",
        url,
    );
}

test "invalid surface IDs are omitted" {
    const url = try buildURL(
        std.testing.allocator,
        "/tmp/readme.md",
        "not-a-surface",
        "/tmp/zashiki-preview-response-abcdefghijklmnopqrstuv",
    );
    defer std.testing.allocator.free(url);

    try std.testing.expectEqualStrings(
        "zashiki://markdown-preview/open?path=%2Ftmp%2Freadme.md&response=%2Ftmp%2Fzashiki-preview-response-abcdefghijklmnopqrstuv",
        url,
    );
}
