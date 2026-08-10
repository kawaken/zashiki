const std = @import("std");

/// Runtime is the runtime to use for Ghostty. All runtimes do not provide
/// equivalent feature sets.
pub const Runtime = enum {
    /// Will not produce an executable at all when `zig build` is called.
    /// This is only useful if you're only interested in the lib only (macOS).
    none,

    pub fn default(target: std.Target) Runtime {
        _ = target;

        // We only support the "none" runtime (macOS, where Xcode builds the
        // app that links to libghostty). This fork does not build a
        // standalone Linux/FreeBSD GUI application.
        return .none;
    }
};

test {
    _ = Runtime;
}
