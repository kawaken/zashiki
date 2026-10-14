const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Action = @import("ghostty.zig").Action;
const global = @import("../global.zig");
const zashiki_url = @import("zashiki_url.zig");

pub const Options = struct {
    pub fn deinit(self: Options) void {
        _ = self;
    }

    pub fn help(self: Options) !void {
        _ = self;
        return Action.help_error;
    }
};

/// Query the running Zashiki instance for the terminal ID associated with the
/// caller's controlling terminal.
///
/// Usage:
///
///   zashiki +terminal-id
///
/// The terminal ID is written to stdout and can be passed to other Zashiki CLI actions.
/// If the caller has no matching Zashiki terminal, the command exits nonzero.
pub fn run(alloc: Allocator) !u8 {
    if (comptime builtin.target.os.tag != .macos) {
        var stderr_buffer: [1024]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(global.io(), &stderr_buffer);
        try stderr_writer.interface.writeAll(
            "The `zashiki +terminal-id` command is only supported on macOS.\n",
        );
        try stderr_writer.end();
        return 1;
    }

    const tty_name = currentTTYName(alloc) catch |err| {
        try writeError("failed to identify the controlling terminal", err);
        return 1;
    } orelse {
        try writeError("no controlling terminal is available", error.NoControllingTerminal);
        return 1;
    };
    defer alloc.free(tty_name);

    const response_path = try zashiki_url.newResponsePath(alloc);
    defer alloc.free(response_path);
    defer std.Io.Dir.deleteFileAbsolute(global.io(), response_path) catch {};

    const url = try buildURL(alloc, tty_name, response_path);
    defer alloc.free(url);

    const response = zashiki_url.sendAndWaitForResponse(alloc, url, response_path) catch |err| {
        try writeError("failed to get a response from Zashiki", err);
        return 1;
    };
    defer alloc.free(response);

    if (std.mem.eql(u8, response, "none")) {
        try writeError("no Zashiki terminal matches the caller's TTY", error.NoMatchingTerminal);
        return 1;
    }
    if (!isTerminalID(response)) {
        try writeError("Zashiki returned an invalid terminal ID", error.InvalidTerminalID);
        return 1;
    }

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(global.io(), &stdout_buffer);
    try stdout_writer.interface.writeAll(response);
    try stdout_writer.interface.writeByte('\n');
    try stdout_writer.end();
    return 0;
}

fn writeError(message: []const u8, err: anyerror) !void {
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(global.io(), &stderr_buffer);
    try stderr_writer.interface.print("zashiki +terminal-id: {s}: {}\n", .{ message, err });
    try stderr_writer.end();
}

fn currentTTYName(alloc: Allocator) !?[]u8 {
    if (comptime builtin.target.os.tag != .macos) return null;

    const c = @cImport({
        @cInclude("fcntl.h");
        @cInclude("unistd.h");
    });

    const fd = c.open("/dev/tty", c.O_RDONLY | c.O_CLOEXEC);
    if (fd < 0) return null;
    defer _ = c.close(fd);

    var buffer: [std.fs.max_path_bytes:0]u8 = undefined;
    if (c.ttyname_r(fd, &buffer, buffer.len) != 0) return null;
    const value = std.mem.sliceTo(&buffer, 0);
    return try alloc.dupe(u8, value);
}

fn buildURL(alloc: Allocator, tty_name: []const u8, response_path: []const u8) ![]u8 {
    var buffer: std.Io.Writer.Allocating = .init(alloc);
    defer buffer.deinit();

    try buffer.writer.writeAll("zashiki://terminal/id?tty=");
    try zashiki_url.appendQueryComponent(&buffer.writer, tty_name);
    try buffer.writer.writeAll("&response=");
    try zashiki_url.appendQueryComponent(&buffer.writer, response_path);
    return buffer.toOwnedSlice();
}

fn isTerminalID(value: []const u8) bool {
    if (value.len != 18 or !std.mem.startsWith(u8, value, "0x")) return false;
    for (value[2..]) |byte| {
        if (!std.ascii.isHex(byte)) return false;
    }
    return true;
}

test "build terminal ID query URL" {
    const url = try buildURL(
        std.testing.allocator,
        "/dev/ttys004",
        "/tmp/zashiki-cli-response-abcdefghijklmnopqrstuv",
    );
    defer std.testing.allocator.free(url);

    try std.testing.expectEqualStrings(
        "zashiki://terminal/id?tty=%2Fdev%2Fttys004&response=%2Ftmp%2Fzashiki-cli-response-abcdefghijklmnopqrstuv",
        url,
    );
}
