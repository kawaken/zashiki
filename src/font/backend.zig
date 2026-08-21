const std = @import("std");

pub const Backend = enum {
    /// CoreText for font discovery, rendering, and shaping (macOS).
    ///
    /// This fork is macOS-only, so CoreText is the only backend. The enum
    /// is kept (rather than removed entirely) because it is threaded
    /// through the build options and reported in crash report tags.
    coretext,

    /// Returns the default backend for a build environment. This is
    /// meant to be called at comptime by the build.zig script. To get the
    /// backend look at build_options.
    pub fn default(target: std.Target) Backend {
        _ = target;
        return .coretext;
    }

    // All the functions below can be called at comptime or runtime to
    // determine if we have a certain dependency.

    pub fn hasFreetype(self: Backend) bool {
        return switch (self) {
            .coretext => false,
        };
    }

    pub fn hasCoretext(self: Backend) bool {
        return switch (self) {
            .coretext => true,
        };
    }

    pub fn hasFontconfig(self: Backend) bool {
        return switch (self) {
            .coretext => false,
        };
    }

    pub fn hasHarfbuzz(self: Backend) bool {
        return switch (self) {
            .coretext => false,
        };
    }
};
