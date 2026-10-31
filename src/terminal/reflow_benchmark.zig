//! Opt-in reflow measurement. Run with ZASHIKI_REFLOW_BENCHMARK=1 and
//! zig build test -Dtest-optimize=ReleaseFast -Dtest-filter='reflow benchmark'.
const std = @import("std");
const Terminal = @import("Terminal.zig");

test "reflow benchmark ASCII CJK emoji history" {
    if (std.c.getenv("ZASHIKI_REFLOW_BENCHMARK") == null) return error.SkipZigTest;
    const alloc = std.heap.page_allocator;
    const io = std.testing.io;
    const widths = [_]u16{ 40, 132, 80, 60, 120, 80, 40, 132, 80, 60, 120, 40, 80 };
    for ([_]struct { name: []const u8, text: []const u8 }{
        .{ .name = "ASCII", .text = "abcdefghij" ** 12 },
        .{ .name = "CJK", .text = "日本語の履歴" ** 10 },
        .{ .name = "emoji", .text = "😀😃😄😁😆😅" ** 10 },
    }) |workload| {
        var t = try Terminal.init(io, alloc, .{
            .cols = 80,
            .rows = 24,
            .max_scrollback_bytes = 50_000_000,
        });
        defer t.deinit(alloc);
        var stream = t.vtStream();
        defer stream.deinit();
        for (0..2_000) |_| {
            stream.nextSlice(workload.text);
            stream.nextSlice("\r\n");
        }
        const before = try t.screens.active.dumpStringAllocUnwrapped(alloc, .{ .screen = .{} });
        defer alloc.free(before);
        // Warm up once, then measure five equivalent resize dances. Fill and
        // correctness checks are outside the timed section.
        for (widths) |cols| try t.resize(alloc, .{ .cols = cols, .rows = 24 });
        for (0..5) |sample| {
            const start = std.Io.Clock.awake.now(io);
            for (widths) |cols| try t.resize(alloc, .{ .cols = cols, .rows = 24 });
            const elapsed = start.durationTo(std.Io.Clock.awake.now(io)).toNanoseconds();
            std.debug.print("REFLOW {s} sample={d} ns={d} rows={d}\n", .{
                workload.name, sample, elapsed, t.screens.active.pages.total_rows,
            });
        }
        const after = try t.screens.active.dumpStringAllocUnwrapped(alloc, .{ .screen = .{} });
        defer alloc.free(after);
        try std.testing.expectEqualStrings(before, after);
    }
}
