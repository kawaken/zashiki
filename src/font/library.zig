//! A library represents the shared state that the underlying font
//! library implementation(s) require per-process.
const std = @import("std");
const Allocator = std.mem.Allocator;
const options = @import("main.zig").options;
const font = @import("main.zig");

/// Library implementation for the compile options.
pub const Library = switch (options.backend) {
    // CoreText doesn't have a "library"
    .coretext => NoopLibrary,
};

pub const NoopLibrary = struct {
    pub const InitError = error{};

    pub fn init(alloc: Allocator) InitError!Library {
        _ = alloc;
        return Library{};
    }

    pub fn deinit(self: *Library) void {
        _ = self;
    }
};
