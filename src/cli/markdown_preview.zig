const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Action = @import("ghostty.zig").Action;
const args = @import("args.zig");
const global = @import("../global.zig");
const zashiki_url = @import("zashiki_url.zig");

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
/// app to confirm that the preview pane opened. `--terminal-id` can be used to
/// target a specific terminal context; without it, the active window is used.
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

    const parsed = parseArgs(alloc) catch |err| switch (err) {
        Action.help_error => return err,
        else => {
            try stderr.writeAll("Usage: zashiki +markdown-preview [--terminal-id <id>] <file.md>\n");
            return 1;
        },
    };
    const path = parsed.path;

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

    const response_path = try zashiki_url.newResponsePath(alloc);
    defer alloc.free(response_path);
    defer std.Io.Dir.deleteFileAbsolute(global.io(), response_path) catch {};

    const url = try buildURL(alloc, absolute_path, parsed.terminal_id, response_path);
    defer alloc.free(url);

    const response = zashiki_url.sendAndWaitForResponse(alloc, url, response_path) catch |err| {
        try stderr.print(
            "zashiki +markdown-preview: failed to get a response from Zashiki: {}\n",
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

const ParsedArgs = struct {
    path: []const u8,
    terminal_id: ?[]const u8,
};

fn parseArgs(alloc: Allocator) !ParsedArgs {
    var iter = try args.argsIterator(alloc, global.args());
    defer iter.deinit();
    return try parseArgsFrom(&iter);
}

fn parseArgsFrom(iter: anytype) !ParsedArgs {
    var path: ?[]const u8 = null;
    var terminal_id: ?[]const u8 = null;
    var end_of_options = false;
    while (iter.next()) |arg| {
        if (!end_of_options and (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h"))) {
            return Action.help_error;
        }
        if (!end_of_options and std.mem.eql(u8, arg, "--")) {
            end_of_options = true;
            continue;
        }
        if (!end_of_options and std.mem.eql(u8, arg, "--terminal-id")) {
            if (terminal_id != null) return error.MultipleTerminalIDs;
            terminal_id = iter.next() orelse return error.MissingTerminalID;
            if (!isTerminalID(terminal_id.?)) return error.InvalidTerminalID;
            continue;
        }
        if (!end_of_options and std.mem.startsWith(u8, arg, "--terminal-id=")) {
            if (terminal_id != null) return error.MultipleTerminalIDs;
            terminal_id = arg["--terminal-id=".len..];
            if (!isTerminalID(terminal_id.?)) return error.InvalidTerminalID;
            continue;
        }
        if (!end_of_options and std.mem.startsWith(u8, arg, "-")) return error.InvalidArgument;
        if (path != null) return error.MultiplePaths;
        path = arg;
    }

    return .{ .path = path orelse return error.MissingPath, .terminal_id = terminal_id };
}

fn buildURL(alloc: Allocator, path: []const u8, terminal_id: ?[]const u8, response_path: []const u8) ![]u8 {
    var buffer: std.Io.Writer.Allocating = .init(alloc);
    defer buffer.deinit();

    try buffer.writer.writeAll("zashiki://markdown-preview/open?path=");
    try zashiki_url.appendQueryComponent(&buffer.writer, path);
    if (terminal_id) |terminal| {
        if (!isTerminalID(terminal)) return error.InvalidTerminalID;
        try buffer.writer.writeAll("&terminal-id=");
        try zashiki_url.appendQueryComponent(&buffer.writer, terminal);
    }
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

test "build markdown preview URL" {
    const url = try buildURL(
        std.testing.allocator,
        "/tmp/日本語 notes.md?draft=true#section",
        "0x0123456789abcdef",
        "/tmp/zashiki-cli-response-abcdefghijklmnopqrstuv",
    );
    defer std.testing.allocator.free(url);

    try std.testing.expectEqualStrings(
        "zashiki://markdown-preview/open?path=%2Ftmp%2F%E6%97%A5%E6%9C%AC%E8%AA%9E%20notes.md%3Fdraft%3Dtrue%23section&terminal-id=0x0123456789abcdef&response=%2Ftmp%2Fzashiki-cli-response-abcdefghijklmnopqrstuv",
        url,
    );
}

test "parse markdown preview terminal ID and path" {
    const alloc = std.testing.allocator;
    var iter = try std.process.Args.IteratorGeneral(.{}).init(
        alloc,
        "--terminal-id 0x0123456789abcdef README.md",
    );
    defer iter.deinit();

    const parsed = try parseArgsFrom(&iter);
    try std.testing.expectEqualStrings("README.md", parsed.path);
    try std.testing.expectEqualStrings("0x0123456789abcdef", parsed.terminal_id.?);
}

test "parse markdown preview without target" {
    const alloc = std.testing.allocator;
    var iter = try std.process.Args.IteratorGeneral(.{}).init(alloc, "README.md");
    defer iter.deinit();

    const parsed = try parseArgsFrom(&iter);
    try std.testing.expectEqualStrings("README.md", parsed.path);
    try std.testing.expect(parsed.terminal_id == null);
}

test "reject invalid markdown preview target" {
    const alloc = std.testing.allocator;
    var iter = try std.process.Args.IteratorGeneral(.{}).init(
        alloc,
        "--terminal-id invalid README.md",
    );
    defer iter.deinit();

    try std.testing.expectError(error.InvalidTerminalID, parseArgsFrom(&iter));
}

test "invalid terminal IDs are rejected" {
    try std.testing.expectError(error.InvalidTerminalID, buildURL(
        std.testing.allocator,
        "/tmp/readme.md",
        "not-a-terminal",
        "/tmp/zashiki-cli-response-abcdefghijklmnopqrstuv",
    ));
}
