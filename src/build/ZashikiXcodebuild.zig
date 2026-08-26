const Zashiki = @This();

const std = @import("std");
const builtin = @import("builtin");
const RunStep = std.Build.Step.Run;
const Config = @import("Config.zig");
const Resources = @import("GhosttyResources.zig");
const XCFramework = @import("GhosttyXCFramework.zig");

build: *std.Build.Step.Run,
open: *std.Build.Step.Run,
copy: *std.Build.Step.Run,
xctest: *std.Build.Step.Run,

pub const Deps = struct {
    xcframework: *const XCFramework,
    resources: *const Resources,
};

pub fn init(
    b: *std.Build,
    config: *const Config,
    deps: Deps,
) !Zashiki {
    const xc_config = switch (config.optimize) {
        .Debug => "Debug",
        .ReleaseSafe,
        .ReleaseSmall,
        .ReleaseFast,
        => "ReleaseLocal",
    };

    const xc_arch: ?[]const u8 = switch (deps.xcframework.target) {
        // Universal is our default target, so we don't have to
        // add anything.
        .universal => null,

        // Native we need to override the architecture in the Xcode
        // project, which we do via `-destination` below.
        .native => switch (builtin.cpu.arch) {
            .aarch64 => "arm64",
            .x86_64 => "x86_64",
            else => @panic("unsupported macOS arch"),
        },
    };

    // Without an explicit destination, xcodebuild matches multiple
    // destinations on a Mac that can run both native and
    // Rosetta-translated binaries (native arch + x86_64 + "Any Mac"),
    // which prints a "using the first of multiple matching destinations"
    // warning and leaves the actual destination up to xcodebuild's own
    // tie-breaking. `-destination` and `-arch` are mutually exclusive
    // (xcodebuild errors if both are given), so every step below passes
    // this instead of a separate `-arch` flag.
    const xc_destination = if (xc_arch) |arch|
        b.fmt("platform=macOS,arch={s}", .{arch})
    else
        "platform=macOS";

    const env = b.graph.environ_map;
    const app_path = b.fmt("macos/build/{s}/Zashiki.app", .{xc_config});

    // The macOS app's version (CFBundleShortVersionString) is derived
    // from `config.version` — build.zig.zon plus git tag/branch
    // detection — rather than being independently maintained as an
    // Xcode MARKETING_VERSION setting. This keeps a single source of
    // truth for the app's version instead of two numbers that can
    // drift apart. See AboutView.swift's VersionConfig for how the
    // macOS UI interprets each shape below.
    const marketing_version = if (config.version.build) |build_metadata|
        // Untagged/dev build: expose the raw short commit hash alone so
        // the About panel recognizes it as a "tip" build.
        build_metadata
    else if (config.version.pre) |pre|
        // Tagged pre-release (e.g. "v0.1.0-rc.1"): not a "stable"
        // format, so it renders as plain text in the About panel.
        b.fmt("{d}.{d}.{d}-{s}", .{
            config.version.major,
            config.version.minor,
            config.version.patch,
            pre,
        })
    else
        // Tagged stable release.
        b.fmt("{d}.{d}.{d}", .{
            config.version.major,
            config.version.minor,
            config.version.patch,
        });
    const marketing_version_arg = b.fmt("MARKETING_VERSION={s}", .{marketing_version});

    // Our step to build the Zashiki macOS app.
    const build = build: {
        // External environment variables can mess up xcodebuild, so
        // we create a new empty environment.
        const env_map = try b.allocator.create(std.process.Environ.Map);
        env_map.* = .init(b.allocator);
        if (env.get("PATH")) |v| try env_map.put("PATH", v);

        const step = RunStep.create(b, "xcodebuild");
        step.has_side_effects = true;
        step.cwd = b.path("macos");
        step.environ_map = env_map;
        step.addArgs(&.{
            "xcodebuild",
            // An old .xcodeproj may remain as Xcode user data after a
            // project rename. Select the repository's project explicitly
            // instead of relying on xcodebuild's directory inference.
            "-project",
            "Zashiki.xcodeproj",
            "-scheme",
            "Zashiki",
            "-configuration",
            xc_config,
            // Force build products into a fixed location (matching
            // `app_path` below) instead of relying on whatever Xcode's
            // per-machine build location preference happens to be
            // (DerivedData vs. legacy project-relative). Without this,
            // the "copy app bundle" step below can silently copy stale
            // or empty output on machines/CI runners that default to
            // DerivedData. Must be an absolute path: a relative SYMROOT
            // breaks Xcode's module search path computation for SPM
            // packages that themselves depend on other SPM packages
            // (e.g. Textual -> SwiftUIMath/ConcurrencyExtras), causing
            // "unable to resolve module dependency" errors.
            b.fmt("SYMROOT={s}", .{b.pathFromRoot("macos/build")}),
            marketing_version_arg,
            "-destination",
            xc_destination,
        });

        // We need the xcframework
        deps.xcframework.addStepDependencies(&step.step);

        // We also need all these resources because the xcode project
        // references them via symlinks.
        deps.resources.addStepDependencies(&step.step);

        // Expect success
        step.expectExitCode(0);

        break :build step;
    };

    const xctest = xctest: {
        const env_map = try b.allocator.create(std.process.Environ.Map);
        env_map.* = .init(b.allocator);
        if (env.get("PATH")) |v| try env_map.put("PATH", v);

        const step = RunStep.create(b, "xcodebuild test");
        step.has_side_effects = true;
        step.cwd = b.path("macos");
        step.environ_map = env_map;
        step.addArgs(&.{
            "xcodebuild",
            "test",
            "-project",
            "Zashiki.xcodeproj",
            "-scheme",
            "Zashiki",
            "-skip-testing",
            "ZashikiUITests",
            "-destination",
            xc_destination,
            // See the comment on the equivalent flag in the `build` step
            // above: keeps output location deterministic across machines.
            // Must be absolute for the same reason noted there.
            b.fmt("SYMROOT={s}", .{b.pathFromRoot("macos/build")}),
            marketing_version_arg,
        });

        // We need the xcframework
        deps.xcframework.addStepDependencies(&step.step);

        // We also need all these resources because the xcode project
        // references them via symlinks.
        deps.resources.addStepDependencies(&step.step);

        // Expect success
        step.expectExitCode(0);

        break :xctest step;
    };

    // Our step to open the resulting Zashiki app.
    const open = open: {
        const disable_save_state = RunStep.create(b, "disable save state");
        disable_save_state.has_side_effects = true;
        disable_save_state.addArgs(&.{
            "/usr/libexec/PlistBuddy",
            "-c",
            // We'll have to change this to `Set` if we ever put this
            // into our Info.plist.
            "Add :NSQuitAlwaysKeepsWindows bool false",
            b.fmt("{s}/Contents/Info.plist", .{app_path}),
        });
        disable_save_state.expectExitCode(0);
        disable_save_state.step.dependOn(&build.step);

        const open = RunStep.create(b, "run Zashiki app");
        open.has_side_effects = true;
        open.cwd = b.path("");
        open.addArgs(&.{b.fmt(
            "{s}/Contents/MacOS/zashiki",
            .{app_path},
        )});

        // Open depends on the app
        open.step.dependOn(&build.step);
        open.step.dependOn(&disable_save_state.step);

        // This overrides our default behavior and forces logs to show
        // up on stderr (in addition to the centralized macOS log).
        open.setEnvironmentVariable("ZASHIKI_LOG", "stderr,macos");

        // Configure how we're launching
        open.setEnvironmentVariable("ZASHIKI_MAC_LAUNCH_SOURCE", "zig_run");

        if (b.args) |args| {
            open.addArgs(args);
        }

        break :open open;
    };

    // Our step to copy the app bundle to the install path.
    // We have to use `cp -R` because there are symlinks in the
    // bundle.
    const copy = copy: {
        const step = RunStep.create(b, "copy app bundle");
        step.addArgs(&.{ "cp", "-R" });
        step.addFileArg(b.path(app_path));
        step.addArg(b.fmt("{s}", .{b.install_path}));
        step.step.dependOn(&build.step);
        break :copy step;
    };

    return .{
        .build = build,
        .open = open,
        .copy = copy,
        .xctest = xctest,
    };
}

pub fn install(self: *const Zashiki) void {
    const b = self.copy.step.owner;
    b.getInstallStep().dependOn(&self.copy.step);
}

pub fn installXcframework(self: *const Zashiki) void {
    const b = self.build.step.owner;
    b.getInstallStep().dependOn(&self.build.step);
}

pub fn addTestStepDependencies(
    self: *const Zashiki,
    other_step: *std.Build.Step,
) void {
    other_step.dependOn(&self.xctest.step);
}
