const std = @import("std");

/// Possible implementations, used for build options.
///
/// This fork is macOS-only, so Metal is the only renderer. The enum is
/// kept (rather than removed entirely) because it is threaded through the
/// build options and reported in crash report tags.
pub const Backend = enum {
    metal,

    pub fn default(target: std.Target) Backend {
        _ = target;
        return .metal;
    }
};
