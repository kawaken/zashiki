//! Exercise the host clipboard boundary with the embedded runtime. Ordinary
//! core tests use the standalone runtime and cannot instantiate its surfaces.
const std = @import("std");

test {
    std.testing.log_level = .err;
    _ = @import("apprt/embedded.zig");
    _ = @import("renderer.zig");
}
