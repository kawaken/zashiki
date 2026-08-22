const std = @import("std");
const posix = std.posix;
const compat_fd = @import("../lib/compat/fd.zig");

/// pipe() with CLOEXEC set on the file descriptors.
pub fn pipe() ![2]posix.fd_t {
    return compat_fd.pipe2(.{ .CLOEXEC = true });
}
